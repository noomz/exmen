# Private signed release candidates

`scripts/release-candidate.sh` creates a private Developer ID-signed, notarized DMG. It does not publish, tag, or push. Run it from a macOS host with Xcode, `gh`, the Exmen Developer ID Application identity, and an existing `notarytool` keychain profile.

Set `RELEASE_VERSION`, `RELEASE_BUILD`, `SPARKLE_FEED_URL`, and `NOTARY_PROFILE` in the environment. The feed must be the reachable production HTTPS appcast. Do not put passwords, private keys, or keychain secrets in these variables or in the repository.

The script downloads each published release's ZIP and DMG assets to inspect their app build numbers. It stops if any published release lacks an inspectable app, history cannot be read, or the requested build does not exceed the maximum. It then archives and exports through Xcode, verifies signatures and the production Sparkle key, notarizes and staples the DMG, and checks the mounted app with Gatekeeper. The resulting private artifact path is printed on success.

The check is a preflight, not a publication lock. Before publishing, recheck release history and verify the exact downloaded bytes under the publication procedure in T5. Publication requires separate approval. Never substitute an ad-hoc artifact if signing or notarization fails.

`ReleaseVersion.xcconfig` holds the default Xcode marketing and build versions. The candidate script supplies the requested version and build as Xcode overrides and verifies both in the exported app.
