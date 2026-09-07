# VAL-FIND-002
**VAL-FIND-002** — Match-case, whole-word, and regex toggles change matching.
Surface: library
Needs: VAL-FIND-001
Behavior: Off/off/off keeps today's smart-case fixed-string match. `Aa` on
  forces case-sensitive. `ab` on requires a word boundary. `.*` on treats
  the query as regex (invalid regex yields a failed snapshot, not a hang).
  Combinations compose. Preserve-case (`AB`) does not affect search, only
  replace (VAL-FIND-006).
Evidence: Persist RED → GREEN `FileSearchMatchFlagTests` asserting rg
  argument mapping and match/no-match fixtures per flag, including invalid
  regex → `.failed`.
Rigor: R2
Why: Flag-to-rg mapping is a pure argument builder with deterministic
  fixtures.
Fail: Regex mode still passing `--fixed-strings`, or an invalid pattern
  leaving the panel in `.searching`.
