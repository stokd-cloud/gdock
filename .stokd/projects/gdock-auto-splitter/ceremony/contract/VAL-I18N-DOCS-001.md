# VAL-I18N-DOCS-001
**VAL-I18N-DOCS-001** - User-facing strings, docs, and build gates cover the feature.
Surface: artifact
Needs: VAL-SETTINGS-001, VAL-SHORTCUT-001, VAL-FORCE-001
Behavior: New Settings rows, command-palette entries, shortcut labels, tooltips,
  context/help text, docs, schema descriptions, and web shortcut data are present
  and localized according to each touched artifact's supported locales; focused
  tests are wired and a tagged gdock build succeeds.
Evidence: Localization catalog parser output, docs/schema grep, `./scripts/lint-pbxproj-test-wiring.sh`,
  focused test commands, and `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock-auto-splitter`.
Rigor: R2
Why: Documentation and localization are user-facing contract surfaces and build
  validation must prove the app and test target both compile.
Fail: Bare English UI strings, missing locale entries, unwired tests, stale
  docs/schema, or relying on `defaultValue` as translation coverage.

---
