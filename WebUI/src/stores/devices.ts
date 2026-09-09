import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { overcueAPI } from '../api/client'
import type {
  DeviceKind,
  DeviceManagementState,
  DeviceSummary,
  OverCUESnapshot,
} from '../api/types'
import { useGroupPresetsStore } from './groupPresets'

const idleManagementState = (): DeviceManagementState => ({
  identifyPurpose: null,
  identifyKind: null,
  identifyLogicalDeviceID: null,
  identifyCandidateCount: 0,
  statusMessage: null,
  errorMessage: null,
})

export const useDevicesStore = defineStore('devices', () => {
  const items = ref<DeviceSummary[]>([])
  const profileNames = ref<string[]>([])
  const management = ref<DeviceManagementState>(idleManagementState())
  const isMutating = ref(false)
  const errorMessage = ref<string | null>(null)
  let identifyPolling = false

  const isIdentifying = computed(() => management.value.identifyPurpose !== null)

  function replace(
    next: DeviceSummary[],
    nextProfileNames: string[] = profileNames.value,
    nextManagement: DeviceManagementState = management.value,
  ) {
    items.value = [...next].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
    profileNames.value = [...nextProfileNames].sort((a, b) => a.localeCompare(b))
    management.value = nextManagement
  }

  function applySnapshot(snapshot: OverCUESnapshot) {
    replace(snapshot.devices, snapshot.profileNames, snapshot.deviceManagement)
    useGroupPresetsStore().replace(
      snapshot.groupPresets,
      snapshot.runtime.activeGroupPresetID,
    )
  }

  async function mutate(operation: () => Promise<OverCUESnapshot>) {
    isMutating.value = true
    errorMessage.value = null
    try {
      const snapshot = await operation()
      applySnapshot(snapshot)
      return snapshot
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
      throw error
    } finally {
      isMutating.value = false
    }
  }

  async function refresh() {
    try {
      const snapshot = await overcueAPI.snapshot()
      applySnapshot(snapshot)
      errorMessage.value = null
      return snapshot
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
      throw error
    }
  }

  async function startIdentifyPolling() {
    if (identifyPolling) return
    identifyPolling = true
    try {
      while (identifyPolling && isIdentifying.value) {
        await new Promise((resolve) => window.setTimeout(resolve, 250))
        if (!identifyPolling) break
        await refresh()
      }
    } finally {
      identifyPolling = false
    }
  }

  async function beginAdd(kind: DeviceKind) {
    await mutate(() => overcueAPI.beginAddDevice(kind))
    void startIdentifyPolling()
  }

  async function beginRebind(id: string, kind?: DeviceKind) {
    await mutate(() => overcueAPI.beginRebindDevice(id, kind))
    void startIdentifyPolling()
  }

  async function cancelIdentify() {
    identifyPolling = false
    await mutate(() => overcueAPI.cancelDeviceIdentify())
  }

  async function rename(id: string, name: string) {
    await mutate(() => overcueAPI.renameDevice(id, name))
  }

  async function assignProfile(id: string, profileName: string) {
    await mutate(() => overcueAPI.assignDeviceProfile(id, profileName))
  }

  async function forgetBinding(id: string) {
    await mutate(() => overcueAPI.forgetDeviceBinding(id))
  }

  function stopIdentifyPolling() {
    identifyPolling = false
  }

  return {
    items,
    profileNames,
    management,
    isIdentifying,
    isMutating,
    errorMessage,
    replace,
    refresh,
    beginAdd,
    beginRebind,
    cancelIdentify,
    rename,
    assignProfile,
    forgetBinding,
    stopIdentifyPolling,
  }
})
