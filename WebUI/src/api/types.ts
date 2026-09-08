export type BridgeStatus = 'running' | 'starting' | 'degraded' | 'stopped' | 'failed'

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

export interface DeviceSummary {
  id: string
  name: string
  profileName: string
  connected: boolean
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
  runtime: RuntimeStatus
}

export interface ReorderRequest {
  ids: string[]
}
