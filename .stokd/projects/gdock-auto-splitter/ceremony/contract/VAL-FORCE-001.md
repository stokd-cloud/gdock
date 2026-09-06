# VAL-FORCE-001
**VAL-FORCE-001** - Force Auto Splitter changes only the last split button into Auto Split.
Surface: artifact
Needs: VAL-SETTINGS-001, VAL-AUTOSPLIT-001
Behavior: With `gdock.forceAutoSplitter == false`, the last split-tab-bar button
  remains the current Split Quad button and produces a 2x2 grid. With
  `gdock.forceAutoSplitter == true`, that button renders as Auto Split with a
  distinct icon/badge/tooltip that reflects the configured rows/columns, and
  clicking it invokes Auto Split. Explicit Split Quad menu/palette/context/CLI
  paths continue to produce a fixed 2x2 grid.
Evidence: Button model tests, Dock appearance tests, tab-bar custom-action tests,
  and a tagged DEBUG dogfood command/screenshot showing the off/on visual and
  topology difference.
Rigor: R2
Why: This is visible UI behavior with compatibility risk for existing Split Quad
  entrypoints, so both visual state and mutation target must be validated.
Fail: Force off changes current UI, force on still creates only 2x2, explicit
  Split Quad surfaces are silently remapped, or the button text/icon is not
  accessibility/localization safe.
