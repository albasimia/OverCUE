import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { DeviceSummary } from '../api/types'

export const useDevicesStore = defineStore('devices', () => {
  const items = ref<DeviceSummary[]>([])

  function replace(next: DeviceSummary[]) {
    items.value = [...next].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
  }

  return { items, replace }
})
