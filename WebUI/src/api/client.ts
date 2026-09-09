import type {
  DeviceIDRequest,
  DeviceIdentifyRequest,
  DeviceKind,
  DeviceProfileRequest,
  DeviceRebindRequest,
  DeviceRenameRequest,
  GroupPresetAssignmentRequest,
  GroupPresetIDRequest,
  GroupPresetIncludeRequest,
  GroupPresetNameRequest,
  GroupPresetRenameRequest,
  OverCUESnapshot,
  ReorderRequest,
  ShortcutEditorCommand,
  ShortcutLiveState,
  ShortcutPanelState,
} from './types'

const API_BASE = import.meta.env.VITE_OVERCUE_API_BASE ?? '/api/v1'
let sessionTokenPromise: Promise<string> | null = null

export class OverCUEAPIError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message)
    this.name = 'OverCUEAPIError'
  }
}

async function errorMessage(response: Response): Promise<string> {
  const body = await response.text().catch(() => '')
  if (body) {
    try {
      const parsed = JSON.parse(body) as { error?: unknown }
      if (typeof parsed.error === 'string' && parsed.error) return parsed.error
    } catch {
      return body
    }
  }
  return response.statusText
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
      ...init?.headers,
    },
  })

  if (!response.ok) {
    throw new OverCUEAPIError(await errorMessage(response), response.status)
  }

  return response.json() as Promise<T>
}

async function sessionToken(): Promise<string> {
  sessionTokenPromise ??= request<{ token: string }>('/session').then(({ token }) => token)
  return sessionTokenPromise
}

async function writeRequest<T>(path: string, body: unknown): Promise<T> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const token = await sessionToken()
    try {
      return await request<T>(path, {
        method: 'PUT',
        headers: { 'X-OverCUE-Session': token },
        body: JSON.stringify(body),
      })
    } catch (error) {
      if (!(error instanceof OverCUEAPIError) || error.status !== 403 || attempt > 0) {
        throw error
      }
      sessionTokenPromise = null
    }
  }
  throw new Error('OverCUE session could not be refreshed.')
}

export const overcueAPI = {
  snapshot: () => request<OverCUESnapshot>('/snapshot'),
  shortcutPanel: () => request<ShortcutPanelState>('/shortcuts/panel'),
  shortcutLive: () => request<ShortcutLiveState>('/shortcuts/live'),
  shortcutCommand: (command: ShortcutEditorCommand) => writeRequest<ShortcutPanelState>(
    '/shortcuts/panel',
    command,
  ),
  reorderPresets: (ids: string[]) => writeRequest<OverCUESnapshot>(
    '/presets/order',
    { ids } satisfies ReorderRequest,
  ),
  reorderGroupPresets: (ids: string[]) => writeRequest<OverCUESnapshot>(
    '/group-presets/order',
    { ids } satisfies ReorderRequest,
  ),
  activateGroupPreset: (id: string) => writeRequest<OverCUESnapshot>(
    '/group-presets/active',
    { id } satisfies GroupPresetIDRequest,
  ),
  addGroupPreset: (name: string) => writeRequest<OverCUESnapshot>(
    '/group-presets/add',
    { name } satisfies GroupPresetNameRequest,
  ),
  renameGroupPreset: (id: string, name: string) => writeRequest<OverCUESnapshot>(
    '/group-presets/rename',
    { id, name } satisfies GroupPresetRenameRequest,
  ),
  deleteGroupPreset: (id: string) => writeRequest<OverCUESnapshot>(
    '/group-presets/delete',
    { id } satisfies GroupPresetIDRequest,
  ),
  setGroupPresetIncluded: (
    groupPresetID: string,
    logicalDeviceID: string,
    included: boolean,
  ) => writeRequest<OverCUESnapshot>(
    '/group-presets/include',
    { groupPresetID, logicalDeviceID, included } satisfies GroupPresetIncludeRequest,
  ),
  assignGroupPreset: (
    groupPresetID: string,
    logicalDeviceID: string,
    presetID: string,
  ) => writeRequest<OverCUESnapshot>(
    '/group-presets/assignment',
    { groupPresetID, logicalDeviceID, presetID } satisfies GroupPresetAssignmentRequest,
  ),
  beginAddDevice: (kind: DeviceKind) => writeRequest<OverCUESnapshot>(
    '/devices/add',
    { kind } satisfies DeviceIdentifyRequest,
  ),
  beginRebindDevice: (id: string, kind?: DeviceKind) => writeRequest<OverCUESnapshot>(
    '/devices/rebind',
    { id, ...(kind ? { kind } : {}) } satisfies DeviceRebindRequest,
  ),
  cancelDeviceIdentify: () => writeRequest<OverCUESnapshot>(
    '/devices/identify/cancel',
    {},
  ),
  renameDevice: (id: string, name: string) => writeRequest<OverCUESnapshot>(
    '/devices/rename',
    { id, name } satisfies DeviceRenameRequest,
  ),
  assignDeviceProfile: (id: string, profileName: string) => writeRequest<OverCUESnapshot>(
    '/devices/profile',
    { id, profileName } satisfies DeviceProfileRequest,
  ),
  forgetDeviceBinding: (id: string) => writeRequest<OverCUESnapshot>(
    '/devices/forget-binding',
    { id } satisfies DeviceIDRequest,
  ),
}
