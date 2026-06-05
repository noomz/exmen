# Raycast Integration Research — Exmen

> Research date: 2026-06-05 · Target: a Raycast extension that lists Exmen "actions" and "services" and runs them by shelling out to the existing `exmen` CLI (which talks to the app over a Unix domain socket at `~/.config/exmen/exmen.sock` using a JSON request/response protocol).

## Overview

Exmen already exposes everything a Raycast extension needs through its CLI: `list-actions`, `run`, `status`, `list-services`, `start-service`, `stop-service`, `restart-service`, `service-status`, all with a `--json` flag on the list commands (see `exmen-cli/main.swift`). The cleanest integration is therefore a **TypeScript/React Raycast extension** that never touches the socket directly — it shells out to `exmen ... --json`, parses the structured response, renders a `List`, and triggers `run`/`start`/`stop`/`restart` from an `ActionPanel`. This keeps the socket protocol entirely inside Swift and gives the extension a stable, versioned contract (the JSON the CLI prints).

The CLI's JSON envelope is uniform: `{ "success": bool, "data": ..., "error": string? }`. `list-actions` → `data: [{name, icon, description, status?}]`; `list-services` → `data: [{name, state, statusText, pid?}]`. The extension should consume the **raw response object via `--json`**, not the pretty human output, and check `success` before reading `data`.

Two delivery options exist: a full **extension** (rich List UI, recommended) or lightweight **Script Commands** (no build step, but no list UI). Recommendation at the end.

## Extension Stack (with versions)

Current as of June 2026:

| Package | Version | Purpose |
|---|---|---|
| `@raycast/api` | **1.104.x** (latest 1.104.18, ~3 days old) | Core UI + system APIs (`List`, `Action`, `showToast`, `Toast`, `environment`) |
| `@raycast/utils` | **^2.x** (`useExec`, `usePromise`, `useCachedPromise`, `showFailureToast`) | Async data hooks + helpers |
| `typescript` | ~5.x | Build language |
| `react` | 18.x (provided/peer via Raycast runtime) | Component model |
| `@raycast/eslint-config` + `eslint`/`prettier` | latest | Lint/format (Store requires lint to pass) |

Runtime: Raycast bundles its own Node runtime; extensions are TypeScript + React with hot reload. Scaffold with the **Create Extension** command inside Raycast (generates `package.json`, `tsconfig`, command entry files, and `assets/`). Dev loop: `npm install && npm run dev` (alias for `ray develop`) — registers commands under a "Development" section with hot reload. `npm run build` (`ray build`) type-checks and produces the distributable bundle.

`package.json` declares each command (name, title, mode `view` vs `no-view`, description, icon) and `preferences` (used below for the binary path).

## Invoking the CLI

**Key pitfall first:** Raycast's extension Node environment does **not** inherit your interactive shell's `PATH`. A bare `exmen` will frequently fail with `command not found` / exit code 127, even though it works in Terminal. Two robust fixes:

1. **Resolve an absolute path** to the binary and call it directly (preferred — avoids shell entirely).
2. **Extend `env.PATH`** passed to the child process.

Expose the binary location as a **preference** so users with non-standard installs can override it, and default to common locations.

```ts
// exmen.ts — single source of truth for invoking the CLI
import { getPreferenceValues, environment } from "@raycast/api";
import { useExec } from "@raycast/utils";

const prefs = getPreferenceValues<{ exmenPath?: string }>();

// Prefer an explicit pref; fall back to common install dirs.
export const EXMEN_BIN = prefs.exmenPath || "/usr/local/bin/exmen"; // also try /opt/homebrew/bin/exmen, ~/.local/bin/exmen

// Pass a sane PATH so child processes can find deps if needed.
export const EXEC_ENV = {
  PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${process.env.PATH ?? ""}`,
};
```

**Reading lists with `useExec`** — use the *file + args array* form (Option 1) so arguments are not shell-escaped, and **avoid `shell: true`** (cross-platform + injection concerns). Parse JSON in `parseOutput`:

```tsx
type ExmenEnvelope<T> = { success: boolean; data?: T; error?: string };
type ActionItem = { name: string; icon?: string; description?: string; status?: string };

const { isLoading, data, error, revalidate } = useExec<ActionItem[]>(
  EXMEN_BIN,
  ["list-actions", "--json"],
  {
    env: EXEC_ENV,
    parseOutput: ({ stdout }) => {
      const env = JSON.parse(stdout) as ExmenEnvelope<ActionItem[]>;
      if (!env.success) throw new Error(env.error ?? "exmen returned an error");
      return env.data ?? [];
    },
  },
);
```

**Running one-shot commands** (run/start/stop) — don't use a hook (hooks are for declarative data). Use `execa`/`child_process` imperatively inside the `Action` handler. `useExec` is built on `execa`; you can import it directly:

```ts
import { execa } from "execa"; // add to dependencies

export async function runAction(name: string) {
  // args array → no manual escaping needed for names with spaces
  const { stdout } = await execa(EXMEN_BIN, ["run", name], { env: EXEC_ENV, timeout: 30_000 });
  return stdout;
}
```

Notes:
- `run <name>` and the service commands take the **name as a positional arg**; passing via an args array handles spaces (e.g. `"Generate Phone Number"`) safely.
- The CLI exits non-zero and writes to **stderr** on failure (`Exmen is not running (socket not found)`, etc.). `execa` rejects on non-zero exit — catch and surface `error.stderr || error.message` in a failure Toast.
- Set a `timeout` (default `useExec` is 10s) — an action could be long-running.

## List + Actions UI

One command per concept keeps it clean: a **"List Actions"** command and a **"Manage Services"** command. Pattern:

```tsx
import { List, ActionPanel, Action, Icon, Color } from "@raycast/api";

export default function ListActions() {
  const { isLoading, data = [], revalidate } = useExec<ActionItem[]>(/* ...as above... */);

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search Exmen actions…">
      {data.map((a) => (
        <List.Item
          key={a.name}
          title={a.name}
          subtitle={a.description}
          accessories={a.status ? [{ tag: a.status }] : []}
          actions={
            <ActionPanel>
              <Action title="Run Action" icon={Icon.Play} onAction={() => onRun(a.name, revalidate)} />
              <Action
                title="Refresh"
                icon={Icon.ArrowClockwise}
                shortcut={{ modifiers: ["cmd"], key: "r" }}
                onAction={revalidate}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
```

For **services**, render `state`/`statusText` and switch the available actions by state — use an accessory tag with color (`green` running, `secondaryText` stopped) and conditionally show Start vs Stop:

```tsx
<List.Item
  title={svc.name}
  subtitle={svc.pid ? `pid ${svc.pid}` : undefined}
  accessories={[{ tag: { value: svc.statusText, color: svc.state === "running" ? Color.Green : Color.SecondaryText } }]}
  actions={
    <ActionPanel>
      {svc.state === "running" ? (
        <Action title="Stop Service" icon={Icon.Stop} style={Action.Style.Destructive} onAction={() => svcCmd("stop-service", svc.name, revalidate)} />
      ) : (
        <Action title="Start Service" icon={Icon.Play} onAction={() => svcCmd("start-service", svc.name, revalidate)} />
      )}
      <Action title="Restart Service" icon={Icon.Repeat} onAction={() => svcCmd("restart-service", svc.name, revalidate)} />
    </ActionPanel>
  }
/>
```

## Async Feedback

Wrap every imperative command in an **animated Toast** that transitions to Success/Failure, then `revalidate()` the list so state (status badges, pid, running/stopped) refreshes:

```tsx
import { showToast, Toast } from "@raycast/api";
import { showFailureToast } from "@raycast/utils";

async function svcCmd(cmd: string, name: string, revalidate: () => void) {
  const toast = await showToast({ style: Toast.Style.Animated, title: `${cmd} ${name}…` });
  try {
    await execa(EXMEN_BIN, [cmd, name], { env: EXEC_ENV, timeout: 30_000 });
    toast.style = Toast.Style.Success;
    toast.title = `${name} ${cmd === "stop-service" ? "stopped" : "started"}`;
    revalidate(); // re-runs list-services --json → UI reflects new state
  } catch (e) {
    await showFailureToast(e, { title: `Failed: ${cmd} ${name}` }); // pulls execa stderr automatically
  }
}
```

- `useExec`/`usePromise` expose `isLoading` (drives `List`'s loading bar) and `revalidate`/`mutate`. `revalidate()` re-executes the same command; `mutate()` supports optimistic updates if you want the toggle to feel instant before the CLI confirms.
- `showFailureToast(error, { title })` from `@raycast/utils` is the idiomatic error path — it surfaces the message and offers a copy action.
- For background refresh while the view is open, re-run `revalidate` on an interval or after each mutating action (latter is enough here).

## Script Commands Alternative

Script Commands are the **pre-extension** mechanism: a single script file (bash/zsh, Python, Node, Swift, AppleScript, Ruby, PHP) with a metadata header comment, dropped into a **Script Directory** registered in Raycast Settings (or created via the *Create Script Command* command). No build, no Node/TypeScript, no Store.

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Run Exmen Action
# @raycast.mode compact
# @raycast.packageName Exmen
# @raycast.argument1 { "type": "text", "placeholder": "action name" }
exmen run "$1"
```

**When preferable:** quick personal use, no UI needed, you only want a handful of fixed commands, you don't want to publish or maintain a TS project. Great for "run my one favorite action."

**Limitations vs a full extension:** no `List`/searchable picker UI (output is limited text/compact/silent/fullOutput modes); arguments are fixed positional prompts, not a live list of the app's current actions; no dynamic enumeration (you can't browse all actions and pick one — you'd hardcode names or paste them); no animated Toast lifecycle; same PATH caveat applies (avoid `-l` login shebangs, which the community repo bans for portability). It cannot stay in sync with the app's action list automatically.

## Distribution

**Local / private development (no Store):**
- `npm run dev` (`ray develop`) — hot-reload dev mode; commands appear under "Development". Fine for personal/internal use indefinitely.
- **Import Extension** command loads a built local extension that you manage yourself (not auto-updated from the Store). This is the route for "ship it alongside Exmen without the public Store" — e.g. ship the extension folder in the Exmen repo and tell users to import it.
- **Private org store:** if part of a Raycast organization, `npm run publish` pushes to your private store (visible only to org members). Requires Raycast org membership.

**Public Raycast Store submission requirements:**
- `package.json`: `author` = your Raycast username, `license` **MIT**, latest `@raycast/api`, at least one **category** (Title Case), `platforms` restricted to macOS if Exmen is mac-only, and a committed `package-lock.json`.
- **Icon:** 512×512 PNG, custom (default Raycast icons are rejected), works in light + dark.
- **Screenshots:** up to 6 (≥3 recommended), 2000×1250 PNG.
- **README.md** required (it needs setup: the `exmen` binary must be installed + the app running) and **CHANGELOG.md** (entries titled in brackets with `{PR_MERGE_DATE}` placeholder).
- `npm run build` and `npm run lint` must pass. Submission is a **PR to `raycast/extensions`** and goes through human review (titles as nouns, Apple Style Guide naming, no broken states).
- A Store extension that depends on an externally-installed CLI is acceptable but reviewers will want graceful handling when the binary/app is missing (see Pitfalls).

## Pitfalls

1. **PATH / binary not found (exit 127):** the #1 issue. Raycast's Node env lacks your shell PATH. Mitigate with an absolute-path **preference** + sensible defaults (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`) and an extended `env.PATH`. On startup, if the resolved path doesn't exist, show an actionable empty-state/Toast ("exmen CLI not found — set its path in extension preferences").
2. **App not running / socket missing:** the CLI exits non-zero with `Exmen is not running (socket not found / connection refused)`. Detect this from `execa`'s rejection (`error.stderr`) and render a clear empty view with a hint to launch Exmen — don't show a raw stack trace.
3. **JSON parsing:** always call list commands with `--json` and parse the **whole envelope**, checking `success` before `data`. The human (non-JSON) output is not stable — never scrape it. Guard `JSON.parse` in `parseOutput` and throw a typed error so the hook's `error` surfaces cleanly. Note the CLI reads up to a 64 KB response buffer; very large action lists could in theory truncate (current design caps at 65536 bytes) — keep an eye on it for large configs.
4. **Names with spaces:** action/service names like `"System Status"` must be passed as a single args-array element (never string-concatenated into a shell command). Using the `useExec(file, args[])` / `execa(file, args[])` forms handles this.
5. **Keeping the extension in sync with the app's action list:** don't hardcode actions — always enumerate via `list-actions --json` at view load and `revalidate` after changes. This makes the UI automatically reflect whatever the user has configured in Exmen, with zero coupling to specific action names. (This is the decisive advantage over Script Commands.)
6. **Auth / permissions for the socket:** the extension never touches the socket — the CLI does, running as the user, and the socket lives under the user's `~/.config`. So there's no extra entitlement/permission for the extension itself. The trust boundary is: extension → user-owned `exmen` binary → user-owned socket. Be mindful that an absolute-path preference is effectively "run this binary" — keep the default pointing at known-good locations and document it.
7. **Timeouts:** `useExec` defaults to 10s; long actions need a higher `timeout`. Set it explicitly on both the hook and imperative `execa` calls.
8. **Concurrent mutations:** disable/avoid firing multiple start/stop on the same service before `revalidate` completes; the animated-Toast-then-revalidate flow naturally serializes user-perceived state.

## Recommendation

Build a **full Raycast extension** (TypeScript + React, `@raycast/api` 1.104.x + `@raycast/utils` 2.x), with two `view` commands — **List Actions** and **Manage Services** — that shell out to the existing `exmen … --json` CLI via `useExec` (lists) and `execa` (mutations). This is the only option that gives a live, searchable, always-in-sync UI by enumerating actions/services at runtime — the core value over Script Commands.

Implementation essentials:
- An **`exmenPath` preference** with sane defaults + extended `env.PATH` to dodge the PATH-not-found pitfall.
- Parse the JSON **envelope** (`success`/`data`/`error`), never the human output.
- Animated **Toast → Success/Failure** around every mutation, then `revalidate()` to refresh state; use `showFailureToast` for errors (surfaces CLI stderr like "Exmen is not running").
- Graceful empty states for "binary not found" and "app not running."

Ship first as a **local/imported extension** bundled in the Exmen repo (zero Store friction, perfect for an open-source companion). Promote to the **public Raycast Store** later once the UX is stable — that adds icon/screenshots/README/CHANGELOG + lint/build gates + a PR review, and should emphasize graceful degradation when the CLI or app is absent. Script Commands remain a fine, documented fallback for power users who just want `exmen run "X"` without installing an extension.

---

### Sources
- [Raycast API — Introduction](https://developers.raycast.com/)
- [@raycast/api — npm](https://www.npmjs.com/package/@raycast/api)
- [Raycast API — useExec](https://developers.raycast.com/utilities/react-hooks/useexec)
- [Raycast API — usePromise](https://developers.raycast.com/utilities/react-hooks/usepromise)
- [Raycast API — Toast / Feedback](https://developers.raycast.com/api-reference/feedback/toast)
- [Raycast API — Best Practices](https://developers.raycast.com/information/best-practices)
- [Raycast API — Environment](https://developers.raycast.com/api-reference/environment)
- [Raycast API — Create Your First Extension](https://developers.raycast.com/basics/create-your-first-extension)
- [Raycast API — Publish a Private Extension](https://developers.raycast.com/teams/publish-a-private-extension)
- [Raycast API — Publish an Extension](https://developers.raycast.com/basics/publish-an-extension)
- [Raycast Manual — Script Commands](https://manual.raycast.com/script-commands)
- [raycast/script-commands — CONTRIBUTING](https://github.com/raycast/script-commands/blob/master/CONTRIBUTING.md)
- [Raycast Blog — Getting started with script commands](https://www.raycast.com/blog/getting-started-with-script-commands)
- [Exmen CLI source — `exmen-cli/main.swift`](file:///Users/noomz/Projects/Opensources/exmen/exmen-cli/main.swift)
