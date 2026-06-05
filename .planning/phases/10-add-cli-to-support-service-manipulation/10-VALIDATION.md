---
phase: 10
slug: add-cli-to-support-service-manipulation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual CLI testing (no automated test framework in project) |
| **Config file** | none |
| **Quick run command** | `echo '{"command":"list-services"}' | nc -U /tmp/exmen.sock` |
| **Full suite command** | `exmen list-services && exmen service-status <name>` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick socket command
- **After every plan wave:** Run full CLI commands
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | SVC-CLI | integration | `echo '{"command":"list-services"}' \| nc -U /tmp/exmen.sock` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | SVC-CLI | integration | `echo '{"command":"start-service","name":"test"}' \| nc -U /tmp/exmen.sock` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | SVC-CLI | integration | `exmen list-services` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — CLI tool and socket server already exist from Phase 6.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Service starts via CLI | SVC-CLI | Requires running service config | Start Exmen, create test service TOML, run `exmen start-service <name>`, verify status dot changes |
| Service stop via CLI | SVC-CLI | Requires running service | Run `exmen stop-service <name>`, verify process terminated |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
