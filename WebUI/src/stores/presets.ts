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

  function syncShortcutPresetOrder(confirmed: PresetSummary[]) {
    const shortcuts = useShortcutsStore()
    const panel = shortcuts.panel
    if (!panel) return

    const currentByID = new Map(panel.presets.map((preset) => [preset.id, preset]))
    const ordered = [...confirmed]
      .sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))
      .flatMap((preset) => {
        const current = currentByID.get(preset.id)
        return current ? [{ ...current, name: preset.name, order: preset.order }] : []
      })

    const selected = panel.presetID
      ? ordered.find((preset) => preset.id === panel.presetID)
      : undefined

    shortcuts.panel = {
      ...panel,
      presets: ordered,
      presetOrder: selected?.order ?? panel.presetOrder,
    }
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
      syncShortcutPresetOrder(snapshot.presets)
    } catch (error) {
      items.value = previous
      throw error
    }
  }

  return { items, replace, reorder }
})
