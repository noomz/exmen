# Isolated signed upgrade channel

This is the private T6 channel. It is not production publication. Do not set `EXMEN_PUBLISH=1`. Do not push tags, GitHub Releases, or `gh-pages`.

## What the channel is

Two Developer ID, hardened-runtime, notarized DMGs, Sparkle-signed with keychain account `exmen` (production public key `u2Qi0V797BF+t7DyxOiHu90S7NLbhIx8S1SlFLvaHiA=`). `SUFeedURL` is an isolated HTTPS origin on the Tart host, `https://192.168.64.1:8443/appcast.xml`. `scripts/publish_release.py --backend local` writes the appcast only after a GET of the versioned URL matches the local SHA-256.

Build with `EXMEN_ISOLATED_CHANNEL=1`. That skips GitHub history, still requires HTTPS, Developer ID, notarization, and the production public key, and refuses isolated hosts unless that flag is set.

`scripts/isolated_feed_server.py` serves the store over TLS. Put the CA and server cert in a scratch directory, not the repo. Trust the CA only inside `mac_jr`.

## Production feed

Production `SUFeedURL` is `https://noomz.github.io/exmen/appcast.xml`, served by GitHub Pages from the root of the `gh-pages` branch (local worktree `../exmen-gh-pages`). The first updater-enabled production build is `1.3.0` build `8` (2026-11-01), which embeds that URL and the production public key. The next release must use a build number above `8`. Staging candidates in this channel use a different `SUFeedURL`, so they are not byte-identical to a production artifact.

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
| keep_alive (first attempt, invalid) | `/bin/sleep` dies on SIGHUP when the PTY closes, so it did not survive. On relaunch `reconnectKeepAliveServices` found the PID dead and deleted the PID file. The later python probe was ended with `killall` (SIGTERM), which skips `willTerminate`, so no PID file was written. |
| keep_alive (retest) | Service `command = "/usr/bin/nohup"`, `args = ["/bin/sleep", "3600"]`, `keep_alive = true`, PID `5345` on build 6. Graceful quit (`osascript ... to quit`) wrote `T6 Keepalive.pid` = `5345`; relaunch showed `running`, PID `5345`. Then Sparkle auto-check showed `Software Update`, `Install Update`, then `Install and Relaunch`. After relaunch: `CFBundleVersion` 7, Exmen PID `5427`, `service-status` `running` on PID `5345`, `list-services` `T6 Keepalive running (pid: 5345)`, `run 'T6 Echo'` printed `t6-echo-okn`. |
| Restore | VM `/Applications/Exmen.app` is build `5` again (build 7 moved to `~/exmen-t6-backup/Exmen-build7.app`). T6 test actions, PID file, and probe process removed. Feed server stopped. Host `/Applications/Exmen.app` was not touched. |

keep_alive services must survive SIGHUP, because Exmen runs services on a PTY and the child gets SIGHUP when the app exits. Run them in the foreground with SIGHUP ignored (for example `nohup`) or use a daemon that ignores SIGHUP. Reconnection relies on the PID file written on `NSApplication.willTerminate`; a SIGTERM or `killall` of Exmen skips it.

The T6 issue with stopping or restarting a reconnected keep_alive service is fixed.

Remove the throwaway CA with:

`tart exec mac_jr /usr/bin/sudo /usr/bin/security remove-trusted-cert -d /tmp/exmen-isolated-ca.crt`

That call hung on a GUI dialog in this run. Do not trust the CA on the host keychain.
