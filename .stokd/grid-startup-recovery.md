# Grid startup recovery — db7c1d9

Original setting observed 2026-09-07: `cloud.stokd.ghostty-dock` / `gdock.gridMode` = true.
Automatic workspace grouping was also enabled. No session snapshots were changed.

Temporary containment: set `gdock.gridMode` to false while repairing runaway compaction.
Do not re-enable Grid Mode in the unfixed main build. The isolated tag uses a separate defaults domain.

Reproduction: live process 44168 ran the same SHA-256 executable as the supplied DerivedData build (e52ab002a513a3de3f4a44e96e3439a12c059af23ccbe20ec812602246b3150c).
Live stack: `scheduleGdockGridModeReconcile` → `reconcileGdockGridModeNow` → `compactGdockGridWorkspaces` → `applyGdockGridShapeAndSpill` → `createWorkspaceInGroup`.

The runaway process was briefly suspended with SIGSTOP, then resumed with SIGCONT after the preference change. It is not left suspended. UI and its exact socket `/Users/stoked/.local/state/cmux/cmux.sock` respond. Both UI and bundled CLI report a stable 526 workspaces. No workspaces or user terminals were deleted.

Acceptance outcomes:
- Test build setup: blocked by missing GhosttyKit.xcframework; repaired using scripts/ensure-ghosttykit.sh, which reused the existing canonical cache. Registered as incidental task 1aee035, with successful artifact validation noted there.
- Test wiring: green (778 test files).
- Compaction regressions: red (five new failures, 46 existing passes), then green (all 51 focused tests pass). Test-only commit 73c0ea30f2; fix commit 911fc13b27; draft PR #41.
- Release grid-startup: build passed on pushed 911fc13b27. Fresh 1x1 startup and four New Terminal actions stayed bounded at five workspaces.
- Restart validation found saved split panels lost because the Grid Mode lock vetoes internal session reconstruction. Dormant placeholder identity is also absent from snapshots. Existing task db7c1d9 was amended and sanctioned for these remaining acceptance line items; new tests precede implementation.
- The new test run was blocked before test execution when an externally owned Sentry cache disappeared. Removed only this task's stale symlink and restored a standalone pinned Sentry 9.3.0 artifact with SHA256 verification. No acceptance red is claimed for that build failure.
- Restore regressions: red (three new failures, 53 other passes, zero skips), then green (all 56 focused tests passed, zero failures/skips). Test-only commit abe07c6bdd; fix commit df69711480. Green result: /tmp/cmux-grid-startup-test/Logs/Test/Test-cmux-unit-2026.09.07_04-31-05--0500.xcresult.
- The updated Release passed on pushed df69711480 in 1203 seconds. Two controlled native quit/relaunch cycles preserved four real terminals, then five real plus three dormant cells across two workspaces. All panel IDs, stable IDs and markers matched. Native click activated only one dormant cell, leaving six real and two dormant; the tagged process was responsive at 0.5% CPU after 100 seconds.
- Initial launch was interrupted by a normal AppKit Quit action before the first identity check. This uncontrolled run is not a claimed pass or crash; the subsequent controlled cycles are the validation evidence.
- Read-only stokd land explain targets main. Do not submit dev_complete admission until explicit user dogfood/merge approval.

## Subsequent user screenshot and main-app relaunch

The user supplied a screenshot showing ordinal Terminal 2080. Live inspection found a different main binary running from /Applications/gdock.app (PID 61194, SHA256 da0587cdd3f2bcde68bcb951675626c8ded9f0dc86009a95c08ae27770c9c7b3), with Grid Mode enabled again. Only gdock.gridMode was set false again. This process was not suspended, killed, or restarted by this agent.

It remained CPU-bound with CLI and native AX requests timing out. Two samples show queued Combine workspace-list notifications repeatedly applying tab-bar configuration to the current entire list. Investigation found a finite-backlog amplification path, not a direct publisher feedback edge. Registered repair 5e692a6. No user workspace or snapshot was deleted. The earlier 526-workspace responsiveness observation applies only to the earlier Desktop process, not this new process.
