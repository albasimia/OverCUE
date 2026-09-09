export type BridgeStatus = 'running' | 'starting' | 'degraded' | 'stopped' | 'failed'
export type DeviceKind = 'ack05' | 'genericHID'

export interface PresetSummary {
  id: string
  name: string
  order: number
  profileName: string
  rekordboxMode: string | null
}

export interface GroupPresetAssignment {
  logicalDeviceID: string
  presetID: string
}

export interface GroupPresetSummary {
  id: string
  name: string
  order: number
  assignments: GroupPresetAssignment[]
}

export interface DevicePresetOption {
  id: string
  name: string
  order: number
}

export interface DeviceBindingSummary {
  kind: DeviceKind
  vendorID: number
  productID: number
  serialNumber: string | null
  lastKnownLocationID: number | null
  bindingIdentifier: string | null
}

export interface DeviceSummary {
  id: string
  name: string
  profileName: string
  connected: boolean
  binding: DeviceBindingSummary | null
  presets: DevicePresetOption[]
}

export interface DeviceManagementState {
  identifyPurpose: 'add' | 'rebind' | null
  identifyKind: DeviceKind | null
  identifyLogicalDeviceID: string | null
  identifyCandidateCount: number
  statusMessage: string | null
  errorMessage: string | null
}

export interface RuntimeStatus {
  inputEnabled: boolean
  bridgeStatus: BridgeStatus
  activeGroupPresetID: string | null
}

export interface OverCUESnapshot {
  presets: PresetSummary[]
  groupPresets: GroupPresetSummary[]
  devices: DeviceSummary[]
  profileNames: string[]
  deviceManagement: DeviceManagementState
  runtime: RuntimeStatus
}

export interface ShortcutAssignment {
  functionName: string
  shortcut: string | null
}

export interface ShortcutKeyState {
  id: string
  assignment: ShortcutAssignment | null
  pressed: boolean
}

export interface ShortcutDialState {
  direction: 'counterclockwise' | 'clockwise'
  assignment: ShortcutAssignment | null
  active: boolean
}

export interface ShortcutPanelState {
  deviceKind: 'ack05'
  deviceName: string
  rotationQuarterTurns: number
  presetID: string | null
  presetName: string | null
  presetOrder: number | null
  keys: ShortcutKeyState[]
  dial: ShortcutDialState[]
}

export interface ReorderRequest {
  ids: string[]
}

export interface GroupPresetIDRequest {
  id: string
}

export interface GroupPresetNameRequest {
  name: string
}

export interface GroupPresetRenameRequest {
  id: string
  name: string
}

export interface GroupPresetIncludeRequest {
  groupPresetID: string
  logicalDeviceID: string
  included: boolean
}

export interface GroupPresetAssignmentRequest {
  groupPresetID: string
  logicalDeviceID: string
  presetID: string
}

export interface DeviceIdentifyRequest {
  kind: DeviceKind
}

export interface DeviceRebindRequest {
  id: string
  kind?: DeviceKind
}

export interface DeviceRenameRequest {
  id: string
  name: string
}

export interface DeviceProfileRequest {
  id: string
  profileName: string
}

export interface DeviceIDRequest {
  id: string
}
