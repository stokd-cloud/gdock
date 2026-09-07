# VAL-FIND-006
**VAL-FIND-006** — Replace previews, scopes, confirms bulk, and undoes.
Surface: library
Needs: VAL-FIND-005
Behavior: Replace-all with more than one file (or a folder/global scope)
  shows a preview of path + line diffs and requires confirm. Scopes are
  current match, current file, current folder, and all results. Preserve
  case (`AB`) preserves identifier case in replacements. Undo restores the
  last successful apply. A failed write rolls back that file and reports it;
  other files already written stay written and remain undoable as a batch.
Evidence: Persist RED → GREEN `FileSearchReplaceApplyTests` for each scope,
  preview payload, confirm gate on multi-file, preserve-case, undo, and
  partial-write failure.
Rigor: R2
Why: Multi-file replace is destructive; preview + undo must be proven
  without launching the app.
Fail: Multi-file replace writing with no preview, or Undo leaving mixed
  new/old content with no error.
