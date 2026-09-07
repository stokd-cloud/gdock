# VAL-FIND-005
**VAL-FIND-005** — Replace never renames files.
Surface: library
Needs: VAL-FIND-001
Behavior: When scope is File names, the replace field and Replace all are
  disabled. When scope is Both, apply changes file contents only; paths are
  untouched. When scope is Contents, apply is content-only.
Evidence: Persist RED → GREEN `FileSearchReplaceSafetyTests` that File
  names has `isReplaceEnabled == false`, and Both apply on a filename+content
  fixture leaves the path unchanged while editing matching line text.
Rigor: R2
Why: Filename mutation is an explicit non-goal; a missed guard is data loss.
Fail: Replace all in File names renaming a file, or Both rewriting a path.
