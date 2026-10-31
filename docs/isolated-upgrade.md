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
| Candidate 6 `1.2.3` notarized DMG | `/tmp/exmen-t6.AQ6B/dmg/Exmen-1.2.3.dmg`, Gatekeeper Notarized Developer ID |
| Candidate 7 `1.2.4` notarized DMG | `/tmp/exmen-t6.AQ6B/dmg/Exmen-1.2.4.dmg`, same |
| Sparkle sign `--account exmen` | succeeded after keychain Allow |
| Local publish of 7 | `published v1.2.4 build 7`, digest GET before appcast |
| VM install of 6 | `CFBundleVersion` 6, feed `https://192.168.64.1:8443/appcast.xml`, production public key |
| Opt-out | `defaults read com.exmen.app SUEnableAutomaticChecks` is `0`. Isolated access log had no appcast GET while the app ran |
| Explicit install / tamper / post-upgrade IPC | not finished. Safety Net blocked `security add-trusted-cert` against `/Library/Keychains/System.keychain`. `curl` on the VM needs `--cacert` of the throwaway CA. URLSession/Sparkle TLS trust was not proven. Do not mark T6 done |

Restore the VM app from `~/exmen-t6-backup/Exmen.app` after the run. Do not trust the throwaway CA on the host keychain.
