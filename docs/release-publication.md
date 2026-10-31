# Publish a signed Exmen release

This guide is for an approved production publication. It does not create GitHub releases, tags, Pages sites, or CI secrets. Run `scripts/publish-release.sh` only after a separate publication approval.

The candidate pipeline in `docs/release-candidate.md` stops at a private notarized DMG. Publication then does this, in order:

1. Sign the finalized DMG with Sparkle (`sign_update --account exmen`).
2. Upload that exact file to a versioned GitHub Releases URL.
3. Download the file from that URL and match its SHA-256 to the local DMG.
4. Write the appcast item only after the digest matches.

A missing file, a digest mismatch, a duplicate build, or a failed appcast write leaves the feed unchanged. Re-running the same version, build, and bytes converges: the script does not add a second enclosure. The reference app in `../agents_usage_bar` writes the appcast before the GitHub release. Do not copy that order.

## Credentials

Keep private material in the login keychain. Never write `.pem` or `.p12` files. Never print a private key, password, or notary profile secret. Never commit credentials.

| Role | Where it lives | Account or name |
| --- | --- | --- |
| Developer ID Application | login keychain codesigning identities | `Developer ID Application: Siriwat Uamngamsup (W6P9Y44LWU)` |
| Notarization | `notarytool` keychain profile | `exmen-notary` |
| Sparkle EdDSA (production) | login keychain, Sparkle account | `exmen` |
| Sparkle EdDSA (tests only) | login keychain, Sparkle account | `exmen-test` |

The production public key is `u2Qi0V797BF+t7DyxOiHu90S7NLbhIx8S1SlFLvaHiA=` in `Exmen/Info.plist` as `SUPublicEDKey`. The test public key is `QqntUJlkHRmJYkETfcUuVScQvfbwRiQguXS9uhn2mUo=`. Do not put the test key in the production plist or any production trust anchor. `scripts/publish-release.sh` refuses `SPARKLE_ACCOUNT=exmen-test` when `BACKEND=github`.

Confirm the pieces without exporting them:

```bash
security find-identity -v -p codesigning | grep 'Developer ID Application: Siriwat Uamngamsup (W6P9Y44LWU)'
xcrun notarytool history --keychain-profile exmen-notary --output-format json --no-progress >/dev/null
.build/artifacts/sparkle/Sparkle/bin/sign_update --account exmen --help >/dev/null
```

GitHub Pages should serve `appcast.xml` over HTTPS at the URL baked into `SUFeedURL`. The publish script writes `appcast.xml` under `APPCAST_DIR` and does not `git push`. After approval, you commit and push that checkout to `gh-pages` yourself. Enable Pages from that branch only when you are ready. Tests use a local directory and a localhost HTTP server. They never call GitHub.

If you later add GitHub Actions secrets, name them without pasting values into the repo or into chat. Do not create those secrets as part of this slice.

## Run publication after approval

Set `EXMEN_PUBLISH=1` only for a real GitHub publish. Point `DMG` at the notarized image from the candidate script. Point `APPCAST_DIR` at a local `gh-pages` checkout. The script calls `sign_update --account exmen` and then `scripts/publish_release.py`.

```bash
EXMEN_PUBLISH=1 \
RELEASE_VERSION=1.2.3 \
RELEASE_BUILD=7 \
DMG=/path/to/Exmen-1.2.3.dmg \
APPCAST_DIR=/path/to/gh-pages \
bash scripts/publish-release.sh
```

Isolated tests use `BACKEND=local`, `STORE`, and `BASE_URL` against a fixture directory. They never call GitHub.

## Recover a lost or rotated Sparkle key

If the `exmen` private key is gone from the keychain and from every backup, already-shipped apps cannot verify a new signature. They stay on the build they have until the user installs a new app that embeds a new `SUPublicEDKey`.

1. Generate a new Sparkle key pair into the login keychain under account `exmen`. Do not write the private key to disk.
2. Put the new public key in `Exmen/Info.plist` as `SUPublicEDKey`.
3. Ship that build as a manual download. Do not expect the old feed to install it.
4. Sign later DMGs with `--account exmen` so they match the new public key.
5. If the old key was leaked, treat the old feed as hostile. Replace `appcast.xml` with items signed by the new key only after users have moved to the new public key.

If only a notary profile or Developer ID identity is missing, restore it from Apple, not from a checked-in file. Publication stays blocked until Developer ID, notarization, and the production Sparkle account are all present.

Rotate `exmen-test` whenever you want. Never point production `SUFeedURL` or `SUPublicEDKey` at it.
