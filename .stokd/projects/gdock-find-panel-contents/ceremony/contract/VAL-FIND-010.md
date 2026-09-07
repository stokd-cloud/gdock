# VAL-FIND-010
**VAL-FIND-010** — Find chrome matches the parked mockup.
Surface: artifact
Needs: VAL-FIND-001, VAL-FIND-006
Behavior: The Find panel shows Contents | File names | Both at all widths.
  Replace and Filters are collapsed by default and expand in place. Compact
  widths stack controls without hiding the scope selector. The expanded
  state matches `.stokd/projects/gdock-find-replace/mockup.png` for control
  presence and grouping (not pixel-identical chrome).
Evidence: Persist a tagged dogfood screenshot of compact and expanded
  Find against `mockup.png`, plus a layout unit test that the scope control
  remains non-zero width at a 240pt panel.
Rigor: R1
Why: Visual contract is the parked mockup; layout collapse is a unit-tested
  width constraint.
Fail: Scope selector scrolling off-screen in a narrow rail, or Replace
  expanded on first open.

---
