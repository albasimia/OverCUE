<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import type {
  RekordboxMode,
  ShortcutDialDirection,
  ShortcutEntryState,
} from '../api/types'
import { useShortcutsStore } from '../stores/shortcuts'

const shortcuts = useShortcutsStore()
const searchText = ref('')
const expandedCategories = ref(new Set<string>(['OverCUE', 'Deck 1']))
const modeOptions: RekordboxMode[] = ['export', 'performance']
const presetEditorMode = ref<'add' | 'rename' | null>(null)
const presetNameDraft = ref('')
const presetMenuOpen = ref(false)
const confirmPresetDelete = ref(false)

onMounted(() => {
  void shortcuts.startPolling()
})

onBeforeUnmount(() => {
  if (shortcuts.panel?.capture.isCapturing) {
    void shortcuts.cancelLearn()
  }
  shortcuts.stopPolling()
})

const panel = computed(() => shortcuts.panel)
const keyByID = computed(() =>
  Object.fromEntries((panel.value?.keys ?? []).map((key) => [key.id, key])),
)
const dialByDirection = computed(() =>
  Object.fromEntries((panel.value?.dial ?? []).map((dial) => [dial.direction, dial])),
)

const mapStyle = computed(() => ({
  '--device-rotation': `${(panel.value?.rotationQuarterTurns ?? 0) * 90}deg`,
  '--label-rotation': `${(panel.value?.rotationQuarterTurns ?? 0) * -90}deg`,
}))

const query = computed(() => searchText.value.trim().toLocaleLowerCase())

const filteredEntries = computed(() => {
  const entries = panel.value?.entries ?? []
  if (!query.value) return entries
  return entries.filter((entry) => [
    entry.description,
    entry.commandID,
    entry.shortcut,
    entry.category,
    ...entry.bindings,
  ].some((value) => value.toLocaleLowerCase().includes(query.value)))
})

const groupedEntries = computed(() => {
  const groups = new Map<string, ShortcutEntryState[]>()
  for (const entry of filteredEntries.value) {
    const values = groups.get(entry.category) ?? []
    values.push(entry)
    groups.set(entry.category, values)
  }
  return [...groups.entries()].map(([category, entries]) => ({ category, entries }))
})

const pressedInput = computed(() => {
  const values = [
    ...(panel.value?.keys ?? []).filter((key) => key.pressed).map((key) => key.id.toUpperCase()),
    ...(panel.value?.dial ?? []).filter((dial) => dial.active).map((dial) =>
      dial.direction === 'clockwise' ? 'DIAL →' : 'DIAL ←'),
  ]
  return values.join(' + ') || '—'
})

const canDeletePreset = computed(() =>
  (panel.value?.presets.length ?? 0) > 1 && panel.value?.presetOrder !== 1,
)

function isExpanded(category: string) {
  return Boolean(query.value) || expandedCategories.value.has(category)
}

function toggleCategory(category: string) {
  if (query.value) return
  const next = new Set(expandedCategories.value)
  if (next.has(category)) next.delete(category)
  else next.add(category)
  expandedCategories.value = next
}

function perform(action: Promise<unknown>) {
  void action.catch(() => undefined)
}

async function revealSelectedEntry() {
  const entryID = shortcuts.panel?.selectedEntryID
  if (!entryID) return
  const entry = shortcuts.panel?.entries.find((candidate) => candidate.id === entryID)
  if (!entry) return

  if (!filteredEntries.value.some((candidate) => candidate.id === entryID)) {
    searchText.value = ''
  }

  const next = new Set(expandedCategories.value)
  next.add(entry.category)
  expandedCategories.value = next
  await nextTick()

  const row = Array.from(
    document.querySelectorAll<HTMLElement>('[data-shortcut-entry-id]'),
  ).find((element) => element.dataset.shortcutEntryId === entryID)
  row?.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' })
}

async function selectKey(keyID: string) {
  try {
    await shortcuts.selectKey(keyID)
    await revealSelectedEntry()
  } catch {
    // Store exposes the native error message.
  }
}

async function selectDial(direction: ShortcutDialDirection) {
  try {
    await shortcuts.selectDial(direction)
    await revealSelectedEntry()
  } catch {
    // Store exposes the native error message.
  }
}

function selectEntry(entryID: string) {
  perform(shortcuts.selectEntry(entryID))
}

function setPreset(event: Event) {
  const presetID = (event.target as HTMLSelectElement).value
  if (presetID) perform(shortcuts.setPreset(presetID))
  presetMenuOpen.value = false
  confirmPresetDelete.value = false
}

function beginAddPreset() {
  presetEditorMode.value = 'add'
  presetNameDraft.value = `Preset ${(panel.value?.presets.length ?? 0) + 1}`
  presetMenuOpen.value = false
  confirmPresetDelete.value = false
}

function beginRenamePreset() {
  if (!panel.value?.presetID) return
  presetEditorMode.value = 'rename'
  presetNameDraft.value = panel.value.presetName ?? ''
  presetMenuOpen.value = false
  confirmPresetDelete.value = false
}

function cancelPresetEditor() {
  presetEditorMode.value = null
  presetNameDraft.value = ''
}

async function savePresetEditor() {
  const name = presetNameDraft.value.trim()
  if (!name) return
  try {
    if (presetEditorMode.value === 'add') {
      await shortcuts.addPreset(name)
    } else if (presetEditorMode.value === 'rename' && panel.value?.presetID) {
      await shortcuts.renamePreset(panel.value.presetID, name)
    }
    cancelPresetEditor()
  } catch {
    // Store exposes the native error message next to the Preset controls.
  }
}

async function deleteCurrentPreset() {
  const presetID = panel.value?.presetID
  if (!presetID || !canDeletePreset.value) return
  if (!confirmPresetDelete.value) {
    confirmPresetDelete.value = true
    return
  }
  try {
    await shortcuts.deletePreset(presetID)
    confirmPresetDelete.value = false
    presetMenuOpen.value = false
  } catch {
    // Store exposes the native error message next to the Preset controls.
  }
}

function setMode(mode: RekordboxMode) {
  if (panel.value?.mode !== mode) perform(shortcuts.setMode(mode))
}

function learn(entryID: string) {
  perform(shortcuts.beginLearn(entryID))
}

function remove(entryID: string) {
  perform(shortcuts.removeBindings(entryID))
}
</script>

<template>
  <section class="shortcuts-page">
    <div class="shortcuts-split">
      <aside class="shortcut-device-pane">
        <div class="shortcut-device-header">
          <div>
            <h2>{{ panel?.deviceName ?? 'ACK05' }}</h2>
            <p>Device Map</p>
          </div>
          <button
            class="shortcut-icon-button"
            type="button"
            title="Rotate device"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            @click="perform(shortcuts.rotateDevice())"
          >
            ↻
          </button>
        </div>

        <div class="shortcut-preset-row">
          <span>Preset</span>
          <select
            :value="panel?.presetID ?? ''"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            aria-label="Preset"
            @change="setPreset"
          >
            <option v-for="preset in panel?.presets ?? []" :key="preset.id" :value="preset.id">
              {{ preset.name }}
            </option>
          </select>
          <button
            class="shortcut-preset-action"
            type="button"
            title="Add Preset"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            @click="beginAddPreset"
          >
            +
          </button>
          <div class="shortcut-preset-menu-wrap">
            <button
              class="shortcut-preset-action"
              type="button"
              title="Manage Preset"
              :disabled="shortcuts.isMutating || panel?.capture.isCapturing || !panel?.presetID"
              @click="presetMenuOpen = !presetMenuOpen; confirmPresetDelete = false"
            >
              …
            </button>
            <div v-if="presetMenuOpen" class="shortcut-preset-menu">
              <button type="button" @click="beginRenamePreset">Rename</button>
              <button
                class="danger"
                type="button"
                :disabled="!canDeletePreset"
                @click="deleteCurrentPreset"
              >
                {{ confirmPresetDelete ? 'Confirm Delete' : 'Delete' }}
              </button>
              <button v-if="confirmPresetDelete" type="button" @click="confirmPresetDelete = false">Cancel</button>
            </div>
          </div>
        </div>

        <div v-if="presetEditorMode" class="shortcut-preset-editor">
          <strong>{{ presetEditorMode === 'add' ? 'Add Preset' : 'Rename Preset' }}</strong>
          <input v-model="presetNameDraft" type="text" @keyup.enter="savePresetEditor" />
          <div>
            <button class="native-button" type="button" @click="cancelPresetEditor">Cancel</button>
            <button
              class="native-button primary"
              type="button"
              :disabled="!presetNameDraft.trim() || shortcuts.isMutating"
              @click="savePresetEditor"
            >
              Save
            </button>
          </div>
        </div>

        <div v-if="shortcuts.errorMessage" class="shortcut-panel-error" role="alert">
          {{ shortcuts.errorMessage }}
        </div>

        <div class="ack05-stage">
          <div class="ack05-rotator" :style="mapStyle">
            <div class="ack05-body">
              <div class="ack05-dial">
                <div class="dial-center" />
                <button
                  class="dial-zone dial-zone-left"
                  :class="{
                    active: dialByDirection.counterclockwise?.active,
                    selected: dialByDirection.counterclockwise?.selected,
                    highlighted: dialByDirection.counterclockwise?.highlighted,
                  }"
                  type="button"
                  @click="selectDial('counterclockwise')"
                >
                  <span class="dial-copy">
                    <b>←</b>
                    <small>{{ dialByDirection.counterclockwise?.assignment?.functionName ?? 'Unassigned' }}</small>
                  </span>
                </button>
                <button
                  class="dial-zone dial-zone-right"
                  :class="{
                    active: dialByDirection.clockwise?.active,
                    selected: dialByDirection.clockwise?.selected,
                    highlighted: dialByDirection.clockwise?.highlighted,
                  }"
                  type="button"
                  @click="selectDial('clockwise')"
                >
                  <span class="dial-copy">
                    <b>→</b>
                    <small>{{ dialByDirection.clockwise?.assignment?.functionName ?? 'Unassigned' }}</small>
                  </span>
                </button>
              </div>

              <div class="ack05-side-mark" />

              <button
                v-for="id in ['k1','k2','k3','k4','k5','k6','k7','k8','k9','k10']"
                :key="id"
                class="ack05-key"
                :class="[
                  id,
                  {
                    pressed: keyByID[id]?.pressed,
                    selected: keyByID[id]?.selected,
                    highlighted: keyByID[id]?.highlighted,
                  },
                ]"
                type="button"
                @click="selectKey(id)"
              >
                <span class="key-copy">
                  <b>{{ id.toUpperCase() }}</b>
                  <small v-if="keyByID[id]?.assignment">{{ keyByID[id]?.assignment?.functionName }}</small>
                </span>
              </button>
            </div>
          </div>
        </div>

        <div class="pressed-readout">
          <span>Input</span>
          <strong>{{ pressedInput }}</strong>
        </div>
      </aside>

      <div class="shortcut-list-pane">
        <div class="shortcut-editor-header">
          <div class="native-page-title">
            <h1>Shortcuts</h1>
            <p>Assign ACK05 or Generic HID input to rekordbox and OverCUE actions.</p>
          </div>

          <div class="shortcut-mode-controls">
            <div class="shortcut-mode-picker" aria-label="rekordbox mode">
              <button
                v-for="mode in modeOptions"
                :key="mode"
                type="button"
                :class="{ active: panel?.mode === mode }"
                :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
                @click="setMode(mode)"
              >
                {{ mode.toUpperCase() }}
              </button>
            </div>
            <button
              class="native-button"
              type="button"
              :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
              @click="perform(shortcuts.reloadMapping())"
            >
              ↻ Reload
            </button>
          </div>
        </div>

        <div v-if="panel?.capture.overwriteMessage" class="shortcut-dialog-backdrop">
          <section
            class="shortcut-overwrite-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="shortcut-overwrite-title"
          >
            <div class="shortcut-dialog-icon" aria-hidden="true">!</div>
            <div class="shortcut-dialog-copy">
              <strong id="shortcut-overwrite-title">Replace existing assignment?</strong>
              <span>{{ panel.capture.overwriteMessage }}</span>
            </div>
            <div class="shortcut-dialog-actions">
              <button class="native-button" type="button" @click="perform(shortcuts.cancelOverwrite())">Cancel</button>
              <button class="native-button primary" type="button" @click="perform(shortcuts.confirmOverwrite())">Replace</button>
            </div>
          </section>
        </div>

        <div v-if="panel?.capture.isCapturing && !panel.capture.overwriteMessage" class="shortcut-capture-panel">
          <div>
            <strong>Learn</strong>
            <span>{{ panel.capture.message ?? 'Press an ACK05 or Generic HID input…' }}</span>
          </div>
          <button class="native-button" type="button" @click="perform(shortcuts.cancelLearn())">Cancel</button>
        </div>

        <div v-if="panel?.capture.error" class="shortcut-panel-error shortcut-top-error" role="alert">
          {{ panel.capture.error }}
        </div>

        <div class="shortcut-search-row">
          <span aria-hidden="true">⌕</span>
          <input v-model="searchText" type="search" placeholder="Search shortcuts" />
          <button v-if="searchText" type="button" @click="searchText = ''">×</button>
        </div>

        <div class="shortcut-mapping-summary">
          <span class="mapping-status-dot" :class="{ error: panel?.mappingError }" />
          <strong>{{ panel?.mappingName ?? 'Loading…' }}</strong>
          <span>{{ panel?.entries.length ?? 0 }} actions</span>
          <code v-if="panel?.mappingFileName">{{ panel.mappingFileName }}</code>
          <span v-if="panel?.mappingError" class="mapping-error">{{ panel.mappingError }}</span>
        </div>

        <div class="shortcut-action-list">
          <div v-if="groupedEntries.length === 0" class="native-empty-state">
            <strong>No shortcuts found.</strong>
            <span>Try a different search.</span>
          </div>

          <section v-for="group in groupedEntries" :key="group.category" class="shortcut-category">
            <button class="shortcut-category-header" type="button" @click="toggleCategory(group.category)">
              <span>{{ isExpanded(group.category) ? '⌄' : '›' }}</span>
              <strong>{{ group.category }}</strong>
              <small>{{ group.entries.length }}</small>
            </button>

            <template v-if="isExpanded(group.category)">
              <div class="shortcut-column-header">
                <span>FUNCTION</span>
                <span>REKORDBOX</span>
                <span>INPUT</span>
              </div>

              <article
                v-for="entry in group.entries"
                :key="entry.id"
                class="shortcut-action-row"
                :class="{
                  selected: panel?.selectedEntryID === entry.id,
                  configured: entry.configured,
                  learning: panel?.capture.entryID === entry.id,
                }"
                :data-shortcut-entry-id="entry.id"
              >
                <button class="shortcut-function-cell" type="button" @click="selectEntry(entry.id)">
                  <span class="configured-mark">{{ entry.configured ? '●' : '○' }}</span>
                  <span class="shortcut-function-copy">
                    <strong>{{ entry.description }}</strong>
                    <small>{{ entry.commandID }}</small>
                  </span>
                </button>

                <span class="shortcut-rekordbox-cell">{{ entry.shortcut || '—' }}</span>

                <div class="shortcut-input-cell">
                  <div class="shortcut-binding-list">
                    <span v-if="entry.bindings.length === 0" class="shortcut-unassigned">Unassigned</span>
                    <template v-else>
                      <span v-for="binding in entry.bindings" :key="binding" class="shortcut-binding-chip">
                        {{ binding }}
                      </span>
                    </template>
                  </div>
                  <button
                    class="shortcut-row-action edit"
                    type="button"
                    title="Learn input"
                    :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
                    @click="learn(entry.id)"
                  >
                    {{ panel?.capture.entryID === entry.id ? '…' : '✎' }}
                  </button>
                  <button
                    class="shortcut-row-action remove"
                    type="button"
                    title="Remove assignments"
                    :disabled="shortcuts.isMutating || panel?.capture.isCapturing || !entry.configured"
                    @click="remove(entry.id)"
                  >
                    ×
                  </button>
                </div>
              </article>
            </template>
          </section>
        </div>
      </div>
    </div>
  </section>
</template>
