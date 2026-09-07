# VAL-FIND-001
**VAL-FIND-001** — Find searches contents, file names, or both.
Surface: library
Needs: none
Behavior: Given a local Find root and a non-empty query, Contents returns
  only in-file text matches; File names returns only path-segment matches;
  Both returns the union, one row identity per file, with filename hits
  distinct from content hits. First-use default scope is Contents. An empty
  query does not search.
Evidence: Persist RED → GREEN `FileSearchScopeTests` covering the three
  scopes against a fixture tree that has a filename hit, a content hit in a
  differently named file, and a file that is both.
Rigor: R2
Why: Scope is the product fork from today's contents-only rg invocation and
  is fully fixture-testable.
Fail: File names returning file contents, or Both collapsing the two hit
  kinds into one undifferentiated list.
