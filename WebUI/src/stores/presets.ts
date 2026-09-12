import { defineStore } from 'pinia'
import { ref } from 'vue'
import { overcueAPI } from '../api/client'
import type { PresetSummary } from '../api/types'
import { useShortcutsStore } from './shortcuts'

export const usePresetsStore = defineStore('presets', () => {
  const items = ref<PresetSummary[]>([])

  function replace(next: PresetSummary[]) {
    items.value = [...next].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))
  }

  async function reorder(ids: string[]) {
    const previous = items.value
    const byID = new Map(previous.map((item) => [item.id, item]))
    items.value = ids.flatMap((id, index) => {
      const item = byID.get(id)
      return item ? [{ ...item, order: index + 1 }] : []
    })
    try {
      const snapshot = await overcueAPI.reorderPresets(ids)
      replace(snapshot.presets)
      useShortcutsStore().syncPresetOrder(snapshot.presets)
    } catch (error) {
      items.value = previous
      throw error
    }
  }

  return { items, replace, reorder }
})
