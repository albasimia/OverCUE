import { defineStore } from 'pinia'
import { overcueAPI } from '../api/client'
import type {
  RekordboxMode,
  ShortcutDialDirection,
  ShortcutEditorCommand,
  ShortcutPanelState,
} from '../api/types'

function delay(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

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
        const nextPanel = await overcueAPI.shortcutPanel()
        if (this.isMutating) return
        this.panel = nextPanel
        this.errorMessage = null
      } catch (error) {
        if (this.isMutating) return
        this.errorMessage = error instanceof Error ? error.message : String(error)
      }
    },

    async refreshLive() {
      if (this.isMutating) return
      const currentPanel = this.panel
      if (!currentPanel) {
        await this.refresh()
        return
      }

      try {
        const previousCapture = currentPanel.capture.isCapturing
        const live = await overcueAPI.shortcutLive()
        if (this.isMutating || this.panel !== currentPanel) return

        const pressedByID = new Map(live.keys.map((key) => [key.id, key.pressed]))
        const activeByDirection = new Map(live.dial.map((dial) => [dial.direction, dial.active]))

        this.panel = {
          ...currentPanel,
          keys: currentPanel.keys.map((key) => ({
            ...key,
            pressed: pressedByID.get(key.id) ?? false,
          })),
          dial: currentPanel.dial.map((dial) => ({
            ...dial,
            active: activeByDirection.get(dial.direction) ?? false,
          })),
          capture: live.capture,
        }
        this.errorMessage = null

        if (previousCapture && !live.capture.isCapturing) {
          await this.refresh()
        }
      } catch (error) {
        if (this.isMutating) return
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

    async addPreset(name: string) {
      await this.command({ action: 'addPreset', name })
      await delay(180)
      await this.refresh()
    },

    async renamePreset(presetID: string, name: string) {
      await this.command({ action: 'renamePreset', presetID, name })
      await delay(80)
      await this.refresh()
    },

    async deletePreset(presetID: string) {
      await this.command({ action: 'deletePreset', presetID })
      await delay(80)
      await this.refresh()
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
      await this.refresh()
      while (this.isPolling && generation === this.pollGeneration) {
        await this.refreshLive()
        await delay(50)
      }
    },

    stopPolling() {
      this.isPolling = false
      this.pollGeneration += 1
    },
  },
})
