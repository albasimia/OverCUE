import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { overcueAPI } from '../api/client'
import type { GroupPresetSummary } from '../api/types'

export const useGroupPresetsStore = defineStore('groupPresets', () => {
  const items = ref<GroupPresetSummary[]>([])
  const activeID = ref<string | null>(null)

  const active = computed(() => items.value.find((item) => item.id === activeID.value) ?? null)

  function replace(next: GroupPresetSummary[], nextActiveID: string | null) {
    items.value = [...next].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))
    activeID.value = nextActiveID
  }

  async function reorder(ids: string[]) {
    const previous = items.value
    const byID = new Map(previous.map((item) => [item.id, item]))
    items.value = ids.flatMap((id, index) => {
      const item = byID.get(id)
      return item ? [{ ...item, order: index + 1 }] : []
    })
    try {
      const snapshot = await overcueAPI.reorderGroupPresets(ids)
      replace(snapshot.groupPresets, snapshot.runtime.activeGroupPresetID)
    } catch (error) {
      items.value = previous
      throw error
    }
  }

  return { items, activeID, active, replace, reorder }
})
