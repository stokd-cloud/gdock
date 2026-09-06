# VAL-SETTINGS-001
**VAL-SETTINGS-001** - Auto Split settings are gdock-owned, bounded, and user-configurable.
Surface: library
Needs: none
Behavior: Missing user config returns rows `2`, columns `2`, force `false`;
  persisted/UserDefaults and `cmux.json` values override those defaults; invalid
  row/column values are clamped to `1...6`; `1 x 1` is treated as a no-op shape.
Evidence: Focused settings tests, schema validation, Settings UI inspection, and
  `cmux.json` readback showing `gdock.autoSplitRows`, `gdock.autoSplitColumns`,
  and `gdock.forceAutoSplitter`.
Rigor: R2
Why: Behavior changes settings persistence and user-facing configuration, so it
  needs persisted evidence and independent validation beyond implementer logs.
Fail: Missing keys, wrong defaults, unbounded pane counts, or fork-owned keys
  placed under upstream prefixes.
