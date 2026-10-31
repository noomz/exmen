# Private signed release candidates

`scripts/release-candidate.sh` creates a private Developer ID-signed, notarized DMG. It does not publish, tag, or push. Run it from a macOS host with Xcode, `gh`, the Exmen Developer ID Application identity, and an existing `notarytool` keychain profile.

Set `RELEASE_VERSION`, `RELEASE_BUILD`, `SPARKLE_FEED_URL`, and `NOTARY_PROFILE` in the environment. The feed must be the reachable production HTTPS appcast. Do not put passwords, private keys, or keychain secrets in these variables or in the repository.

The script downloads each published release's ZIP and DMG assets to inspect their app build numbers. It stops if any published release lacks an inspectable app, history cannot be read, or the requested build does not exceed the maximum. It then archives and exports through Xcode, verifies signatures and the production Sparkle key, notarizes and staples the DMG, and checks the mounted app with Gatekeeper. The resulting private artifact path is printed on success.

The check is a preflight, not a publication lock. Before publishing, recheck release history and verify the exact downloaded bytes under the publication procedure in T5. Publication requires separate approval. Never substitute an ad-hoc artifact if signing or notarization fails.

`ReleaseVersion.xcconfig` holds the default Xcode marketing and build versions. The candidate script supplies the requested version and build as Xcode overrides and verifies both in the exported app.

## T4 private candidate verification

The production feed does not exist yet, so the script's feed gate was not bypassed. Candidate 6 was prepared by hand using the same archive and export commands in the script, Developer ID team `W6P9Y44LWU`, version `1.2.2`, and the non-production placeholder `https://example.invalid/exmen-test/appcast.xml`. Xcode exported the nested Sparkle code with Developer ID signing and hardened runtime. The exported app was packaged into a signed DMG, submitted with `xcrun notarytool submit --keychain-profile exmen-notary --wait`, then stapled and validated.

Apple accepted submission `de23290c-c55e-4168-aa82-395693d7c7ff`. The final DMG SHA-256 was `c986f91b11d1b8adec1a237da51d5b3417a087bf0dcf829caca4b2e2e4826b45`. In `mac_jr`, a copied DMG had the same digest and passed `stapler validate` and `spctl -a -vvv -t open --context context:primary-signature`. Its mounted app passed `spctl -a -vvv`, `codesign --verify --deep --strict`, and individual checks of Sparkle's Autoupdate, Updater.app, Installer.xpc, and Downloader.xpc. A copy of that app ran a test action and started and stopped a test service over CLI/socket IPC.

This private candidate is not a production artifact: its feed is intentionally invalid. Run the complete script against the real production feed after T5/T6 configures it. Verify the actual uploaded and downloaded distribution bytes before publication.
