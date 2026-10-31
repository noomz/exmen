# Exmen settings and updates

## §G Goal

Give Exmen users native settings, login launch, app information, and signed, user-approved updates.

## §C Constraints

- macOS 13 minimum. Keep menu-bar-only behavior and existing action, service, and IPC behavior.
- Use Sparkle, as in `../agents_usage_bar`. Do not copy its unsigned release fallback.
- Publish only Developer ID signed, hardened-runtime, notarized releases. Missing credentials or failed validation block publication.
- Automatic update checks default on. Users can turn them off. Manual checks remain available. Installation requires explicit user approval.
- Never commit Apple credentials or Sparkle private keys. Use a separate Exmen Sparkle key; do not reuse the reference app's key.
- Preserve bundle identity unless migration is explicitly planned. Existing ad-hoc or differently signed installs may require manual replacement before entering the signed update chain.
- This spec plans work only. Production releases, secret provisioning, and external configuration require explicit execution approval.

## §I Interfaces

- I1. Menu bar exposes Settings. Settings opens as a standalone native window.
- I2. Settings presents Launch on startup, automatic update checks, Check for Updates, and About. About displays app name, bundle version, and build number.
- I3. Login registration uses `SMAppService.mainApp` and macOS Login Items.
- I4. Sparkle uses an HTTPS appcast and verifies updates with Exmen's embedded public key.
- I5. GitHub Releases hosts versioned artifacts. GitHub Pages hosts the production appcast, subject to repository setup.
- I6. Release operator supplies Developer ID, notarization, and Sparkle credentials through protected CI secrets or an approved local signing process.

## §V Invariants

- V1. Opening Settings repeatedly focuses one usable window. Closing it leaves Exmen and its menu bar running. No persistent Dock icon appears.
- V2. About and menu version text read actual bundle metadata. `CFBundleShortVersionString` and `CFBundleVersion` derive from one release version source, not hardcoded UI strings.
- V3. Login toggle reflects actual `SMAppService` status, not a cached preference. Registration changes only after explicit user action. Failure or approval-required status is visible and offers a path to Login Items. Refresh status when Settings regains focus.
- V4. Update check preference persists across relaunch. Off prevents scheduled checks, including at launch. Manual checking remains available. On permits scheduled checks. Neither setting silently installs updates.
- V5. Manual check reports availability, no update, and errors through Sparkle's native interaction. Check control reflects updater availability and does not create overlapping checks.
- V6. Sparkle verifies update signatures before installation. Invalid signature, malformed feed, unreachable feed, or failed download cannot replace the running app.
- V7. Every public release uses the user's Developer ID Application identity, hardened runtime, notarization, and appropriate stapling. Verify nested Sparkle code and Gatekeeper assessment on the final downloaded distribution artifact. No unsigned or ad-hoc release fallback.
- V8. Published build numbers strictly exceed every previously published build number. First determine the highest shipped `CFBundleVersion`; current source plist says 5 while project says 1. Do not assume either is the published maximum. A rollback is a new, higher build.
- V9. Release artifact is finalized before Sparkle signing. Upload and verify the exact signed bytes at a versioned URL before making the appcast entry visible. Failed or repeated runs do not expose a missing, mismatched, duplicate, or partially published update.
- V10. Production feed and public key are present in the first updater-enabled release. Private keys never appear in source, logs, or artifacts. A key loss or rotation procedure is documented before production use.
- V11. A signed release with Sparkle embedded still runs actions, CLI/socket requests, and managed services. User-approved update and relaunch preserve existing service shutdown and `keep_alive` reconnection rules without duplicate processes or sockets.
- V12. Real upgrade validation uses two distinct increasing builds and verifies installed version, signature, relaunch, and app behavior. Test feeds and test identities cannot become production trust anchors. Do not expose test entries to production users.
- V13. Existing SPM GUI build and Xcode build remain usable. CLI build output never overwrites the GUI executable or binds its socket.

## §T Ordered slices

Each slice ends in a working, reviewable state. Do not ship a placeholder control that claims to work. UI slices require screenshots and a live macOS check. All slices require relevant tests and the Xcode test suite where practical.

| id | status | slice and acceptance evidence | cites |
|---|---|---|---|
| T1 | x | Add accessible Settings window and About. Unify bundle version metadata and replace hardcoded menu version. Open, close, reopen, and inspect actual bundle values; verify menu and IPC still work. | I1,I2,V1,V2,V13 |
| T2 | x | Add login toggle backed by `SMAppService`. Cover enabled, disabled, approval, and failure states with tests. Test registration and removal from an installed app, including System Settings changes and relaunch. | I2,I3,V1,V3 |
| T3 | x | Embed Sparkle and provide functional automatic-check preference and manual check. Use isolated test feed and test key, never production feed. Exercise opt-out, manual checks, offline/error, invalid signature, and consent using installed test builds. Preserve both build paths. | I2,I4,V4,V5,V6,V12,V13 |
| T4 | x | Prepare signed release pipeline with Sparkle embedded, version source, monotonic build check, notarization, and final-artifact verification. Run a non-public signed candidate; verify Gatekeeper, nested signatures, actions, services, and IPC. Fail closed on missing credentials. | I5,I6,V2,V7,V8,V10,V11 |
| T5 | x | Implement idempotent release publication and appcast generation. Verify artifact upload and downloaded digest before appcast visibility. Test retry, missing artifact, duplicate build, and partial failure against isolated fixtures or private staging. Document secret setup and recovery. | I4,I5,I6,V6,V8,V9,V10,V12 |
| T6 | x | Prove end-to-end upgrade between increasing signed, notarized builds in an isolated channel. Check opt-out, explicit install approval, tampered update rejection, installed version, service reconnection, socket, and action execution. Document production feed configuration and first-install migration. Production publication requires separate approval. | I1,I2,I4,I5,V4,V5,V6,V7,V8,V9,V10,V11,V12 |

## §B Bugs

| id | date | cause | fix |
|---|---|---|---|

## Execution notes

- `Exmen/ExmenApp.swift` owns the menu-bar scene and startup lifecycle. `Exmen/Views/MenuContentView.swift` currently hardcodes `v1.2`.
- `Exmen/Info.plist` currently hardcodes version `1.2` and build `5`. `Exmen.xcodeproj/project.pbxproj` currently sets marketing version `1.2` and build `1`.
- `../agents_usage_bar/.github/workflows/release.yml` demonstrates Sparkle signing and notarization, but publishes its appcast before creating the GitHub Release. Do not copy that ordering.
- Xcode tests run with `xcodebuild test -project Exmen.xcodeproj -scheme Exmen -destination 'platform=macOS'`. `swift test` has no test target.
- Verify whether a production appcast, signing identity, and previous published builds already exist before configuring CI. Never inspect or print secret values.
- Staging feed and production feed can require differently configured app bundles. Verify the actual production-configured signed artifact as well as the isolated upgrade path. Do not claim byte-identical staging promotion unless demonstrated.
- Operator reviews Settings interactions before merge. No production tag, release, or public appcast update without separate approval.
