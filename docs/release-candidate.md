# Private signed release candidates

`scripts/release-candidate.sh` creates a private Developer ID-signed, notarized DMG. It does not publish, tag, or push. Run it from a macOS host with Xcode, `gh`, the Exmen Developer ID Application identity, and an existing `notarytool` keychain profile.

Set `RELEASE_VERSION`, `RELEASE_BUILD`, `SPARKLE_FEED_URL`, and `NOTARY_PROFILE` in the environment. The feed must be the reachable production HTTPS appcast. Do not put passwords, private keys, or keychain secrets in these variables or in the repository.

The script downloads each published release's ZIP and DMG assets to inspect their app build numbers. It stops if any published release lacks an inspectable app, history cannot be read, or the requested build does not exceed the maximum. It then archives and exports through Xcode, verifies signatures and the production Sparkle key, notarizes a ZIP of the app, and staples the app. It packages that stapled app into a DMG, notarizes and staples the DMG, then validates both tickets and checks the mounted app with Gatekeeper. The resulting private artifact path is printed on success.

The check is a preflight, not a publication lock. Before publishing, recheck release history and verify the exact downloaded bytes with `scripts/publish-release.sh` as described in `docs/release-publication.md`. Publication requires separate approval. Never substitute an ad-hoc artifact if signing or notarization fails.

`ReleaseVersion.xcconfig` holds the default Xcode marketing and build versions. The candidate script supplies the requested version and build as Xcode overrides and verifies both in the exported app.

## T4 private candidate verification

The production feed does not exist yet, so the script's feed gate was not bypassed. Candidate 6 was prepared by hand using the same archive and export commands in the script, Developer ID team `W6P9Y44LWU`, version `1.2.2`, and the non-production placeholder `https://example.invalid/exmen-test/appcast.xml`. Xcode exported the nested Sparkle code with Developer ID signing and hardened runtime. `scripts/notarize-candidate.sh` submitted the app ZIP and the resulting DMG with the `exmen-notary` keychain profile and stapled each artifact.

Apple accepted app submission `306f9926-bfa0-4935-bc10-fabb92887724` and DMG submission `7cac79d1-cebd-4772-a0d7-41d43ee5bd0b`. The final DMG SHA-256 was `36adfa4e6020507ad3a018dac3ec146dce8fcf3e887fb9157cee781a0e4c5557`. In `mac_jr`, a copied DMG had the same digest. Both the DMG and its mounted app passed `stapler validate` and Gatekeeper assessment; the mounted app also passed `codesign --verify --deep --strict`.

The previous candidate, submission `de23290c-c55e-4168-aa82-395693d7c7ff`, had a stapled DMG but no app ticket. Its Gatekeeper and IPC smoke checks passed, but it did not satisfy the requirement to staple both artifacts.

This private candidate is not a production artifact: its feed is intentionally invalid. Run the complete script against the real production feed after T5/T6 configures it. Verify the actual uploaded and downloaded distribution bytes before publication.
