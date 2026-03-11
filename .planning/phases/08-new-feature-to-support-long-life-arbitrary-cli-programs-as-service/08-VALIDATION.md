---
phase: 8
slug: long-running-cli-services
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — manual testing via Xcode Run |
| **Config file** | None |
| **Quick run command** | `xcodebuild -scheme Exmen -configuration Debug build 2>&1 \| grep -E "error:\|BUILD"` |
| **Full suite command** | Manual: build + launch + exercise all service states |
| **Estimated runtime** | ~30 seconds (build), manual testing varies |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild -scheme Exmen -configuration Debug build 2>&1 | grep -E "error:|BUILD"` (compile check)
- **After every plan wave:** Full manual smoke test: launch app, configure test service, start/stop/restart, view output
- **Before `/gsd:verify-work`:** All behaviors below pass
- **Max feedback latency:** ~30 seconds (build time)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | Service TOML parsing | manual | build succeeds + config loads | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 1 | Start/stop via context menu | manual | visual inspection | ❌ W0 | ⬜ pending |
| 08-01-03 | 01 | 1 | Status dot updates | manual | visual inspection | ❌ W0 | ⬜ pending |
| 08-02-01 | 02 | 2 | PTY terminal emulation | manual | run service, check `tput colors` | ❌ W0 | ⬜ pending |
| 08-02-02 | 02 | 2 | Output window independent | manual | visual inspection | ❌ W0 | ⬜ pending |
| 08-02-03 | 02 | 2 | Restart policy enforced | manual | crash service, observe | ❌ W0 | ⬜ pending |
| 08-02-04 | 02 | 2 | keep_alive behavior | manual | quit app, check `ps` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing infrastructure covers compile-check verification
- All functional testing is manual (native macOS GUI app)

*No automated test framework to install — validation is build success + manual smoke testing.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Service starts/stops correctly | Lifecycle control | GUI interaction required | Right-click service → Start, verify green dot, right-click → Stop |
| Output window shows streaming output | Output viewing | Visual inspection of live output | Start chatty service, verify output streams in window |
| PTY programs work (colors, cursor) | Terminal emulation | Visual inspection of terminal rendering | Start `htop` or `python3 -i` as service, verify display |
| Restart policy triggers | Restart on failure | Requires controlled crash | Start service with `sleep 2 && exit 1`, verify restart |
| keep_alive survives quit | Process persistence | Requires app lifecycle test | Set keep_alive=true, quit Exmen, check `ps aux` |
| Menu shows separate sections | Menu layout | Visual inspection | Configure both services and actions, verify divider |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
