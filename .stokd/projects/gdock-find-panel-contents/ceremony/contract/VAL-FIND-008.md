# VAL-FIND-008
**VAL-FIND-008** — Files, terminal Find, and browser Find stay as they are.
Surface: library
Needs: none
Behavior: `FileExplorerPanelPresentation.files` does not gain the Find
  scope selector, replace field, or grouped-results table. Cmd+F in a
  terminal surface still opens terminal find; Cmd+F in a browser surface
  still opens browser find. Cmd+Shift+F still focuses the Find rail.
Evidence: Persist RED → GREEN `FileExplorerFindIsolationTests` plus existing
  `find` / `findInDirectory` shortcut routing tests remaining green.
Rigor: R1
Why: Isolation is a regression against already-passing shortcut tests.
Fail: Files presentation rendering Replace all, or Cmd+F stealing terminal
  find into the rail.
