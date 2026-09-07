## Fix

- Stop Grid Mode reconciliation from multiplying real terminals: discard unactivated layout placeholders before reshaping, and seed spill workspaces with the existing overflow panel instead of starting another terminal.
- Keep placeholder activation suppressed across grouped compaction and preserve real panels when transfers fail.
- Make full-grid New Terminal rollover create exactly one new real terminal.
- Allow internal session reconstruction through the Grid Mode user split lock, preserving every saved panel instead of replacing saved splits with empty terminals.
- Persist unused grid-cell identity in a backward-compatible optional terminal payload field. Keep restored cells dormant until activation, without inherited command/input or agent/tmux resume work; legacy snapshots and Grid Mode-off restores remain usable.

## Regression evidence

- Test-only commit `73c0ea30f2`: all five new behavior tests failed; 46 existing focused tests passed.
- Fix commit `911fc13b27`: all 51 Grid Mode and automatic-group tests passed; zero failures or skipped tests.
- Tests cover repeated grouped reconciliation, 1x1 overflow, failed overflow transfer, failed compaction transfer, and full-grid rollover.
- Restart test-only commit `abe07c6bdd`: all three new regressions failed; the other 53 tests passed, including legacy and Grid Mode-off guardrails.
- Restore fix commit `df69711480`: all 56 focused tests passed with zero failures/skips. Round-trip tests check complete saved-panel mappings, dormant-cell persistence, held runtime admission after restore commit, and explicit activation.
- Test wiring passed for 778 files; `git diff --check` passed.
- Localization audit: no user-facing strings, settings keys, shortcuts, or help text changed.

## Dogfood

- Initial tagged Release build passed on `911fc13b27`; fresh 1x1 startup and repeated New Terminal actions stayed bounded. Relaunch testing exposed the additional saved-layout/placeholder defects now covered above.
- Updated tagged Release build passed on pushed `df69711480` in 1203 seconds.
- Controlled native menu quit/relaunch preserved all four real terminal IDs. Full-grid Cmd-T then produced exactly five real terminals and three dormant cells across two workspaces. A second normal quit/relaunch preserved every panel ID, stable surface ID, and dormant marker; the live CLI reported two workspaces, eight panes/surfaces, and five TTYs.
- Clicking one restored dormant pane activated exactly one cell: six real terminals, two still dormant, unchanged workspace/panel counts. The live tagged process remained responsive at 0.5% CPU after 100 seconds.
- One initial launch was interrupted by a normal AppKit Quit action before verification completed; it is not claimed as a successful identity check or a crash. Subsequent controlled cycles are the evidence above.
- Dogfood build: http://127.0.0.1:17320/grid-startup. User approval is still required before merging; the repo's automatic landing target is main, so no dev_complete admission has been requested.
- The existing user's session was preserved; Grid Mode was temporarily disabled only for recovery. No workspaces or saved snapshots were deleted.
- No merge approval is implied by this PR.
