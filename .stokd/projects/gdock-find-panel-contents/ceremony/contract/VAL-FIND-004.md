# VAL-FIND-004
**VAL-FIND-004** — Both groups filename hits and nests content matches.
Surface: library
Needs: VAL-FIND-001
Behavior: In Both, a file with a filename hit shows a `NAME` badge and
  count; content matches nest under that file; a file that is only a
  content hit has no `NAME` badge. Duplicate file rows are not listed.
  Contents-only and File-names-only do not show the opposite hit kind.
Evidence: Persist RED → GREEN `FileSearchResultGroupingTests` for Both
  nesting, Contents-only (no NAME rows), and File-names-only (no nested
  content rows).
Rigor: R2
Why: Grouping is the observable difference from the current flat
  `FileSearchResult` table.
Fail: Both showing two rows for the same file, or Contents showing NAME
  badges.
