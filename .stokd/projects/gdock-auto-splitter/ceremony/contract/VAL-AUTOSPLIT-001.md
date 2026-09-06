# VAL-AUTOSPLIT-001
**VAL-AUTOSPLIT-001** - Auto Split creates the configured terminal grid through one shared path.
Surface: library
Needs: VAL-SETTINGS-001
Behavior: Auto Split replaces the focused source pane with a deterministic
  `rows x columns` terminal grid; preserves the original surface in the top-left
  cell; creates the remaining cells as new terminals; focuses the bottom-right
  cell by default; returns failure without local partial mutation for known vetoes
  and remote-tmux unsupported lanes.
Evidence: Table-driven main/Dock Auto Split tests for `1 x 2`, `2 x 1`, `2 x 2`,
  `2 x 3`, and clamped invalid values; existing Split Quad tests remain green by
  delegating 2x2 behavior through the same action family.
Rigor: R2
Why: The pane tree mutation affects live terminals and Dock ownership; validator
  coverage must prove topology and failure behavior, not just symbol presence.
Fail: Duplicate per-entrypoint algorithms, partial remote/local grids on veto,
  lost original surface, wrong focus target, or Split Quad regressions.
