import { defineStore } from 'pinia'
import { overcueAPI } from '../api/client'
import type {
  RekordboxMode,
  ShortcutDialDirection,
  ShortcutEditorCommand,
  ShortcutPanelState,
} from '../api/types'

export const useShortcutsStore = defineStore('shortcuts', {
  state: () => ({
    panel: null as ShortcutPanelState | null,
    errorMessage: null as string | null,
    isPolling: false,
    pollGeneration: 0,
    isMutating: false,
  }),

  actions: {
    async refresh() {
      if (this.isMutating) return
      try {
        this.panel = await overcueAPI.shortcutPanel()
        this.errorMessage = null
      } catch (error) {
        this.errorMessage = error instanceof Error ? error.message : String(error)
      }
    },

    async command(command: ShortcutEditorCommand) {
      if (this.isMutating) return
      this.isMutating = true
      try {
        this.panel = await overcueAPI.shortcutCommand(command)
        this.errorMessage = null
      } catch (error) {
        this.errorMessage = error instanceof Error ? error.message : String(error)
        throw error
      } finally {
        this.isMutating = false
      }
    },

    selectEntry(entryID: string) {
      return this.command({ action: 'selectEntry', entryID })
    },

    selectKey(keyID: string) {
      return this.command({ action: 'selectKey', keyID })
    },

    selectDial(direction: ShortcutDialDirection) {
      return this.command({ action: 'selectDial', direction })
    },

    setPreset(presetID: string) {
      return this.command({ action: 'setPreset', presetID })
    },

    addPreset(name: string) {
      return this.command({ action: 'addPreset', name })
    },

    renamePreset(presetID: string, name: string) {
      return this.command({ action: 'renamePreset', presetID, name })
    },

    deletePreset(presetID: string) {
      return this.command({ action: 'deletePreset', presetID })
    },

    setMode(mode: RekordboxMode) {
      return this.command({ action: 'setMode', mode })
    },

    reloadMapping() {
      return this.command({ action: 'reload' })
    },

    beginLearn(entryID: string) {
      return this.command({ action: 'beginLearn', entryID })
    },

    cancelLearn() {
      return this.command({ action: 'cancelLearn' })
    },

    removeBindings(entryID: string) {
      return this.command({ action: 'removeBindings', entryID })
    },

    confirmOverwrite() {
      return this.command({ action: 'confirmOverwrite' })
    },

    cancelOverwrite() {
      return this.command({ action: 'cancelOverwrite' })
    },

    rotateDevice() {
      return this.command({ action: 'rotateDevice' })
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
