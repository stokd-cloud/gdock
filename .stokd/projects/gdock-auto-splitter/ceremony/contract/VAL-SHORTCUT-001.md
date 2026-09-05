# VAL-SHORTCUT-001
**VAL-SHORTCUT-001** - Cmd+Y triggers Auto Split through the configurable shortcut system.
Surface: artifact
Needs: VAL-SETTINGS-001
Behavior: With no user override, Cmd+Y invokes Auto Split for the focused main or
  Dock pane; the action is visible/editable in Settings, supported by
  `shortcuts.bindings`, documented in shortcut data/docs, and has no default
  shortcut collision. User overrides and explicit unbinds take precedence.
Evidence: Shortcut registry tests, NSEvent routing tests, settings package tests,
  schema enum validation, and docs/shortcut data diff.
Rigor: R2
Why: A default keyboard shortcut is a product-wide input contract that must be
  independently validated against conflict and routing behavior.
Fail: Cmd+Y does nothing, collides with another default action, bypasses
  `KeyboardShortcutSettings`, or cannot be customized/unbound.
