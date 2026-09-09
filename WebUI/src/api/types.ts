export type BridgeStatus = 'running' | 'starting' | 'degraded' | 'stopped' | 'failed'
export type DeviceKind = 'ack05' | 'genericHID'
export type RekordboxMode = 'export' | 'performance'
export type ShortcutDialDirection = 'counterclockwise' | 'clockwise'

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

export interface ShortcutPresetOption {
  id: string
  name: string
  order: number
  mode: RekordboxMode | null
}

export interface ShortcutKeyState {
  id: string
  assignment: ShortcutAssignment | null
  pressed: boolean
  selected: boolean
  highlighted: boolean
}

export interface ShortcutDialState {
  direction: ShortcutDialDirection
  assignment: ShortcutAssignment | null
  active: boolean
  selected: boolean
  highlighted: boolean
}

export interface ShortcutEntryState {
  id: string
  commandID: string
  description: string
  shortcut: string
  category: string
  isInternal: boolean
  configured: boolean
  bindings: string[]
}

export interface ShortcutCaptureState {
  isCapturing: boolean
  entryID: string | null
  message: string | null
  error: string | null
  overwriteMessage: string | null
}

export interface ShortcutPanelState {
  deviceKind: 'ack05'
  deviceName: string
  rotationQuarterTurns: number
  presetID: string | null
  presetName: string | null
  presetOrder: number | null
  presets: ShortcutPresetOption[]
  mode: RekordboxMode
  mappingName: string
  mappingFileName: string | null
  mappingError: string | null
  selectedEntryID: string | null
  selectedKeyID: string | null
  selectedDialDirection: ShortcutDialDirection | null
  keys: ShortcutKeyState[]
  dial: ShortcutDialState[]
  entries: ShortcutEntryState[]
  capture: ShortcutCaptureState
}

export type ShortcutEditorAction =
  | 'selectEntry'
  | 'selectKey'
  | 'selectDial'
  | 'setPreset'
  | 'setMode'
  | 'reload'
  | 'beginLearn'
  | 'cancelLearn'
  | 'removeBindings'
  | 'confirmOverwrite'
  | 'cancelOverwrite'
  | 'rotateDevice'

export interface ShortcutEditorCommand {
  action: ShortcutEditorAction
  entryID?: string
  keyID?: string
  direction?: ShortcutDialDirection
  presetID?: string
  mode?: RekordboxMode
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
