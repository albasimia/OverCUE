# Preset order reconciliation fix

2026-09-12

## Symptom

After reordering Presets in the Web UI, the Preset dropdown could settle on the order from the previous reorder operation instead of the newly persisted order.

## Cause

`OverCUEConfigurationOrdering.reorderPresets` correctly persisted the new order, but `ShortcutSettingsModel` later reconciled its in-memory configuration against the updated file through `OverCUEConfigurationSnapshotSynchronizer`.

`OverCUEConfigurationMerger.mergePresetGroups` treated a stale local `order` difference as an unsaved local edit and overlaid it onto the newer remote snapshot. This made the in-memory Shortcut model lag one reorder behind the persisted configuration.

The same ownership ambiguity existed for Group Preset `order`.

## Resolution

Preset and Group Preset ordering are now treated as persisted/file-store-owned fields during snapshot reconciliation:

- existing Preset `order` always follows the remote persisted snapshot;
- existing Group Preset `order` always follows the remote persisted snapshot;
- local name, mapping, and assignment changes continue to use the existing three-way merge semantics;
- newly added local entities still retain their local values through the existing add/remove merge path.

Added `ConfigurationReconciliationTests` covering remote-order precedence while preserving legitimate local field changes.

## Verification gate

Run:

```bash
swift test
swift run OverCUE
```

Then reorder Presets repeatedly without leaving Shortcuts. After each drop/save, the Preset dropdown must immediately reflect the exact latest order rather than the previous operation's order.
