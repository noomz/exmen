# Isolated signed upgrade channel

This is the private T6 channel. It is not production publication. Do not set `EXMEN_PUBLISH=1`. Do not push tags, GitHub Releases, or `gh-pages`.

## What the channel is

Two Developer ID, hardened-runtime, notarized DMGs, Sparkle-signed with keychain account `exmen` (production public key `u2Qi0V797BF+t7DyxOiHu90S7NLbhIx8S1SlFLvaHiA=`). `SUFeedURL` is an isolated HTTPS origin on the Tart host, `https://192.168.64.1:8443/appcast.xml`. `scripts/publish_release.py --backend local` writes the appcast only after a GET of the versioned URL matches the local SHA-256.

Build with `EXMEN_ISOLATED_CHANNEL=1`. That skips GitHub history, still requires HTTPS, Developer ID, notarization, and the production public key, and refuses isolated hosts unless that flag is set.

`scripts/isolated_feed_server.py` serves the store over TLS. Put the CA and server cert in a scratch directory, not the repo. Trust the CA only inside `mac_jr`.

## Production feed

Production `SUFeedURL` must be the HTTPS GitHub Pages URL that will serve `appcast.xml` from `gh-pages`. It is not configured yet. The first updater-enabled production build must embed that URL and the production public key. Staging candidates in this channel use a different `SUFeedURL`, so they are not byte-identical to a production artifact.

## First-install migration

Unsigned and pre-Sparkle installs cannot join this chain. Measured:

- `Exmen-v1.2.1.zip` in the repo is not signed and has no `SUFeedURL` or `SUPublicEDKey`.
- The `mac_jr` app before T6 was Developer ID build `5` with no Sparkle keys. `UpdateConfiguration.isValid` leaves the updater off when those keys are missing.
- Sparkle 2 verifies EdDSA against the embedded public key and does not install across a missing key.

Users on builds `<= 5` (ad-hoc or signed without Sparkle) must replace the app by hand with a Developer ID, notarized build that already contains the production public key and production feed. Sparkle cannot reach them.

## T6 run (2026-10-31)

| Check | Result |
| --- | --- |
| Candidate 6 `1.2.3` | notarized DMG, Gatekeeper Notarized Developer ID |
| Candidate 7 `1.2.4` | same |
| Sparkle sign `--account exmen` | succeeded |
| Local publish of 7 | digest GET then appcast |
| VM install of 6 | `CFBundleVersion` 6, isolated HTTPS feed, production public key |
| Opt-out | `SUEnableAutomaticChecks` 0, no appcast GET |
| Tamper | copy of 7 at `/tamper/good.dmg` with mutated `edSignature`. Sparkle: `Update Error!` `The update is improperly signed and could not be validated.` |
| Explicit approval | `Software Update` then `Install Update`, then `Ready to Install` / `Install and Relaunch` |
| Installed version | `CFBundleVersion` 7 after relaunch, process `5109` |
| Socket / CLI | `/tmp/exmen-t6-cli list-actions --json` returned T6 Echo. `run 'T6 Echo'` printed `t6-echo-okn` |
| keep_alive | `/bin/sleep` started before upgrade did not survive Sparkle replace. After 7, a SIGHUP-immune python keep_alive PID `5223` survived `killall` and Quit Exmen, but `~/.config/exmen/services` had no PID file so the app showed `stopped` after relaunch. Reconnect of the pre-upgrade service was not shown. |
| Restore | VM `/Applications/Exmen.app` is build `5` again. Host `/Applications/Exmen.app` was not touched. |

SPEC T6 stays open until keep_alive reconnection after the Sparkle relaunch is shown with a PID file and `service-status` still `running` on the same PID.

Remove the throwaway CA with:

`tart exec mac_jr /usr/bin/sudo /usr/bin/security remove-trusted-cert -d /tmp/exmen-isolated-ca.crt`

That call hung on a GUI dialog in this run. Do not trust the CA on the host keychain.
