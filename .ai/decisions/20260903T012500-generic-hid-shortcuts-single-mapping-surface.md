# Decision: Generic HID mapping is edited only in Shortcuts

Date: 2026-09-03

## Context

Generic HID registration and real SIDE-KEYBOARD descriptor validation succeeded, but the first implementation added a separate Generic HID mapping UI under Devices. That duplicated the existing Shortcuts mapping workflow and required the normal Generic HID runtime to release an exclusive IOHIDManager before a second Learn monitor could seize the same composite HID. On macOS this produced `kIOReturnExclusiveAccess` / `kIOReturnNotPrivileged` failures during runtime-to-Learn handoff.

## Decision

- Devices owns Physical Binding, Logical Device metadata, Profile assignment and Group Preset assignment only.
- Shortcuts is the single mapping editor for ACK05 and Generic HID.
- One Shortcuts edit session listens for both ACK05 and registered Generic HID input; the first captured physical input wins.
- Generic HID Learn MUST reuse the already-running Generic HID runtime as the exclusive owner. It does not close the runtime or open a second IOHIDManager.
- During Shortcuts capture, the ACK05 CLI process is temporarily stopped and the existing Generic HID runtime switches to capture mode. Generic HID events are intercepted before Action Layer routing.
- After capture, the same Generic HID IOHIDManager remains open and only ACK05 runtime is resumed. No Generic HID exclusive ownership handoff occurs.
- `generic-hid.json` remains an adapter persistence detail for now; it is not a second mapping UI or user-facing source of truth. A future schema consolidation may move these physical descriptors into the main config after runtime behavior is proven.

## Consequences

- SIDE-KEYBOARD native Keypad / Consumer Control behavior stays suppressed while OverCUE input is enabled.
- Shortcuts capture no longer depends on fixed delays or `IOHIDManagerClose` release timing for Generic HID.
- Existing Generic HID assignments remain visible in the Shortcuts INPUT column.
- Rebind remains a Devices operation and may still use the shared Identify path; mapping Learn no longer uses `GenericHIDLearnMonitor`.
