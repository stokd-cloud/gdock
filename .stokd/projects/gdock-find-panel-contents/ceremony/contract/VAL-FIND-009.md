# VAL-FIND-009
**VAL-FIND-009** — New strings, settings, and shortcuts are catalogued.
Surface: artifact
Needs: VAL-FIND-001
Behavior: Every new user-facing string has `String(localized:)` keys in
  `Resources/Localizable.xcstrings` (en+ja). New settings live under
  `gdock.find*` in `GdockCatalogSection` (not `app.*` / `sidebar.*`). New
  replace/toggle shortcuts are `KeyboardShortcutSettings` actions, editable
  in Settings and `cmux.json`. New tests have pbxproj source entries.
Evidence: Localization audit of added keys; schema grep for `gdock.find`;
  `./scripts/lint-pbxproj-test-wiring.sh` exit 0.
Rigor: R1
Why: Catalog and localization are grep-checkable; wiring is an existing
  scripted gate.
Fail: Hardcoded English in Find chrome, or a new test file that xcodebuild
  never compiles.
