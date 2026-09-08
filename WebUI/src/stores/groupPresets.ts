import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { overcueAPI } from '../api/client'
import type { GroupPresetSummary, OverCUESnapshot } from '../api/types'

export const useGroupPresetsStore = defineStore('groupPresets', () => {
  const items = ref<GroupPresetSummary[]>([])
  const activeID = ref<string | null>(null)

  const active = computed(() => items.value.find((item) => item.id === activeID.value) ?? null)

  function replace(next: GroupPresetSummary[], nextActiveID: string | null) {
    items.value = [...next].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))
    activeID.value = nextActiveID
  }

  function applySnapshot(snapshot: OverCUESnapshot) {
    replace(snapshot.groupPresets, snapshot.runtime.activeGroupPresetID)
  }

  async function reorder(ids: string[]) {
    const previous = items.value
    const byID = new Map(previous.map((item) => [item.id, item]))
    items.value = ids.flatMap((id, index) => {
      const item = byID.get(id)
      return item ? [{ ...item, order: index + 1 }] : []
    })
    try {
      applySnapshot(await overcueAPI.reorderGroupPresets(ids))
    } catch (error) {
      items.value = previous
      throw error
    }
  }

  async function activate(id: string) {
    applySnapshot(await overcueAPI.activateGroupPreset(id))
  }

  async function add(name: string) {
    applySnapshot(await overcueAPI.addGroupPreset(name))
  }

  async function rename(id: string, name: string) {
    applySnapshot(await overcueAPI.renameGroupPreset(id, name))
  }

  async function remove(id: string) {
    applySnapshot(await overcueAPI.deleteGroupPreset(id))
  }

  async function setIncluded(
    groupPresetID: string,
    logicalDeviceID: string,
    included: boolean,
  ) {
    applySnapshot(await overcueAPI.setGroupPresetIncluded(
      groupPresetID,
      logicalDeviceID,
      included,
    ))
  }

  async function assignPreset(
    groupPresetID: string,
    logicalDeviceID: string,
    presetID: string,
  ) {
    applySnapshot(await overcueAPI.assignGroupPreset(
      groupPresetID,
      logicalDeviceID,
      presetID,
    ))
  }

  return {
    items,
    activeID,
    active,
    replace,
    reorder,
    activate,
    add,
    rename,
    remove,
    setIncluded,
    assignPreset,
  }
})
