# VAL-FIND-007
**VAL-FIND-007** — Opening a content hit lands on the recorded line.
Surface: library
Needs: VAL-FIND-004
Behavior: Activating a nested content row opens that file at
  `lineNumber`/`columnNumber` from the rg match. Activating a filename-only
  row opens the file without requiring a line jump. Missing files produce a
  status error, not a crash.
Evidence: Persist RED → GREEN `FileSearchOpenTargetTests` that the open
  command carries path + line + column for content hits and path-only for
  NAME rows.
Rigor: R1
Why: Line targeting is a single command payload; persistence of the unit
  test is the evidence floor.
Fail: Opening a content hit at line 1 regardless of the match line.
