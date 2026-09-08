import { defineStore } from 'pinia'
import { overcueAPI } from '../api/client'
import type { ShortcutPanelState } from '../api/types'

export const useShortcutsStore = defineStore('shortcuts', {
  state: () => ({
    panel: null as ShortcutPanelState | null,
    errorMessage: null as string | null,
    isPolling: false,
    pollGeneration: 0,
  }),

  actions: {
    async refresh() {
      try {
        this.panel = await overcueAPI.shortcutPanel()
        this.errorMessage = null
      } catch (error) {
        this.errorMessage = error instanceof Error ? error.message : String(error)
      }
    },

    async startPolling() {
      if (this.isPolling) return
      this.isPolling = true
      const generation = ++this.pollGeneration
      while (this.isPolling && generation === this.pollGeneration) {
        await this.refresh()
        await new Promise((resolve) => window.setTimeout(resolve, 50))
      }
    },

    stopPolling() {
      this.isPolling = false
      this.pollGeneration += 1
    },
  },
})
