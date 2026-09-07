# VAL-FIND-003
**VAL-FIND-003** — Filters limit which files are candidates.
Surface: library
Needs: VAL-FIND-001
Behavior: Include globs restrict candidates; exclude globs drop them;
  "use ignore files" on honors `.gitignore` / rg ignore (today's default);
  off searches ignored files too. Limit All searches the Find root; Open
  restricts to open editors; Changed restricts to git-dirty paths in that
  root. Globs apply to both content and filename candidates.
Evidence: Persist RED → GREEN `FileSearchFilterTests` with include/exclude
  fixtures, ignore on/off, and Open/Changed candidate sets.
Rigor: R2
Why: Candidate filtering is independent of result chrome and must not
  silently disagree with the tree's ignore rules.
Fail: Exclude glob still returning hits, or Changed including clean files.
