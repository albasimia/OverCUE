<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import ACK05DeviceMap from '../components/ACK05DeviceMap.vue'
import { overcueAPI } from '../api/client'
import type {
  RekordboxMode,
  ShortcutDialDirection,
  ShortcutEntryState,
} from '../api/types'
import { useSortableOrder } from '../composables/useSortableOrder'
import { usePresetsStore } from '../stores/presets'
import { useSettingsStore } from '../stores/settings'
import { useShortcutsStore } from '../stores/shortcuts'

const shortcuts = useShortcutsStore()
const settings = useSettingsStore()
const presets = usePresetsStore()
const searchText = ref('')
const expandedCategories = ref(new Set<string>(['OverCUE', 'Deck 1']))
const modeOptions: RekordboxMode[] = ['export', 'performance']
const presetEditorMode = ref<'add' | 'rename' | null>(null)
const presetNameDraft = ref('')
const presetMenuOpen = ref(false)
const confirmPresetDelete = ref(false)
const presetReorderOpen = ref(false)
const presetReorderElement = ref<HTMLElement | null>(null)
const presetReorderLoadError = ref<string | null>(null)

const { isSaving: isReorderingPresets, errorMessage: presetReorderError } = useSortableOrder({
  element: presetReorderElement,
  currentIDs: () => presets.items.map((preset) => preset.id),
  persist: async (ids) => {
    await presets.reorder(ids)
    await shortcuts.refresh()
  },
})

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

const categoryKeys: Record<string, string> = {
  OverCUE: 'shortcuts.overcue',
  Browse: 'category.browse',
  'Deck 1': 'category.deck1',
  'Deck 2': 'category.deck2',
  'Deck 3': 'category.deck3',
  'Deck 4': 'category.deck4',
  'All Decks': 'category.allDecks',
  Sampler: 'category.sampler',
  Recordings: 'category.recordings',
  General: 'category.general',
  View: 'category.view',
  Playlist: 'category.playlist',
  Other: 'category.other',
}

function categoryLabel(category: string) {
  return settings.text(categoryKeys[category] ?? category)
}

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
  presetNameDraft.value = settings.text('preset.defaultName', (panel.value?.presets.length ?? 0) + 1)
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

async function refreshPresetStore() {
  const snapshot = await overcueAPI.snapshot()
  presets.replace(snapshot.presets)
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
    await refreshPresetStore()
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
    await refreshPresetStore()
    confirmPresetDelete.value = false
    presetMenuOpen.value = false
  } catch {
    // Store exposes the native error message next to the Preset controls.
  }
}

async function openPresetReorder() {
  presetMenuOpen.value = false
  confirmPresetDelete.value = false
  presetReorderLoadError.value = null
  try {
    await refreshPresetStore()
    presetReorderOpen.value = true
  } catch (error) {
    presetReorderLoadError.value = error instanceof Error ? error.message : String(error)
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
            <p>{{ settings.text('device.map') }}</p>
          </div>
          <button
            class="shortcut-icon-button"
            type="button"
            :title="settings.text('device.rotate')"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            @click="perform(shortcuts.rotateDevice())"
          >
            ↻
          </button>
        </div>

        <div class="shortcut-preset-row">
          <span>{{ settings.text('device.group') }}</span>
          <select
            :value="panel?.presetID ?? ''"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            :aria-label="settings.text('device.group')"
            @change="setPreset"
          >
            <option v-for="preset in panel?.presets ?? []" :key="preset.id" :value="preset.id">
              {{ preset.name }}
            </option>
          </select>
          <button
            class="shortcut-preset-action"
            type="button"
            :title="settings.text('preset.add')"
            :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
            @click="beginAddPreset"
          >
            +
          </button>
          <div class="shortcut-preset-menu-wrap">
            <button
              class="shortcut-preset-action"
              type="button"
              :title="settings.text('preset.manage')"
              :disabled="shortcuts.isMutating || panel?.capture.isCapturing || !panel?.presetID"
              @click="presetMenuOpen = !presetMenuOpen; confirmPresetDelete = false"
            >
              …
            </button>
            <div v-if="presetMenuOpen" class="shortcut-preset-menu">
              <button type="button" @click="beginRenamePreset">{{ settings.text('preset.rename') }}</button>
              <button type="button" @click="openPresetReorder">{{ settings.text('preset.reorder') }}</button>
              <button
                class="danger"
                type="button"
                :disabled="!canDeletePreset"
                @click="deleteCurrentPreset"
              >
                {{ confirmPresetDelete ? settings.text('preset.delete.title') : settings.text('preset.delete') }}
              </button>
              <button v-if="confirmPresetDelete" type="button" @click="confirmPresetDelete = false">
                {{ settings.text('common.cancel') }}
              </button>
            </div>
          </div>
        </div>

        <div v-if="presetReorderLoadError" class="shortcut-panel-error" role="alert">
          {{ presetReorderLoadError }}
        </div>

        <div v-if="presetEditorMode" class="shortcut-preset-editor">
          <strong>{{ presetEditorMode === 'add' ? settings.text('preset.add.title') : settings.text('preset.rename.title') }}</strong>
          <input v-model="presetNameDraft" type="text" @keyup.enter="savePresetEditor" />
          <div>
            <button class="native-button" type="button" @click="cancelPresetEditor">{{ settings.text('common.cancel') }}</button>
            <button
              class="native-button primary"
              type="button"
              :disabled="!presetNameDraft.trim() || shortcuts.isMutating"
              @click="savePresetEditor"
            >
              {{ settings.text('common.save') }}
            </button>
          </div>
        </div>

        <div v-if="shortcuts.errorMessage" class="shortcut-panel-error" role="alert">
          {{ shortcuts.errorMessage }}
        </div>

        <ACK05DeviceMap
          :rotation-quarter-turns="panel?.rotationQuarterTurns ?? 0"
          :keys="panel?.keys ?? []"
          :dial="panel?.dial ?? []"
          :unassigned-label="settings.text('common.unassigned')"
          @select-key="selectKey"
          @select-dial="selectDial"
        />

        <div class="pressed-readout">
          <span>{{ settings.text('shortcuts.column.input') }}</span>
          <strong>{{ pressedInput }}</strong>
        </div>
      </aside>

      <div class="shortcut-list-pane">
        <div class="shortcut-editor-fixed">
          <div class="shortcut-editor-header">
            <div class="native-page-title">
              <h1>{{ settings.text('shortcuts.title') }}</h1>
            </div>

            <div class="shortcut-mode-controls">
              <div class="shortcut-mode-picker" :aria-label="settings.text('shortcuts.mode')">
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
                :title="settings.text('shortcuts.reload.help')"
                :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
                @click="perform(shortcuts.reloadMapping())"
              >
                ↻ {{ settings.text('shortcuts.reload') }}
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
                <strong id="shortcut-overwrite-title">{{ settings.text('alert.overwrite.title') }}</strong>
                <span>{{ panel.capture.overwriteMessage }}</span>
              </div>
              <div class="shortcut-dialog-actions">
                <button class="native-button" type="button" @click="perform(shortcuts.cancelOverwrite())">
                  {{ settings.text('common.cancel') }}
                </button>
                <button class="native-button primary" type="button" @click="perform(shortcuts.confirmOverwrite())">
                  {{ settings.text('alert.overwrite.action') }}
                </button>
              </div>
            </section>
          </div>

          <div v-if="panel?.capture.isCapturing && !panel.capture.overwriteMessage" class="shortcut-capture-panel">
            <div>
              <strong>{{ settings.text('shortcuts.learn') }}</strong>
              <span>{{ panel.capture.message ?? settings.text('message.capturePrompt') }}</span>
            </div>
            <button class="native-button" type="button" @click="perform(shortcuts.cancelLearn())">
              {{ settings.text('common.cancel') }}
            </button>
          </div>

          <div v-if="panel?.capture.error" class="shortcut-panel-error shortcut-top-error" role="alert">
            {{ panel.capture.error }}
          </div>

          <div class="shortcut-search-row">
            <span aria-hidden="true">⌕</span>
            <input v-model="searchText" type="search" :placeholder="settings.text('shortcuts.search')" />
            <button v-if="searchText" type="button" @click="searchText = ''">×</button>
          </div>

          <div class="shortcut-mapping-summary">
            <span class="mapping-status-dot" :class="{ error: panel?.mappingError }" />
            <strong>{{ panel?.mappingName ?? settings.text('message.loading') }}</strong>
            <span>{{ settings.text('shortcuts.actions', panel?.entries.length ?? 0) }}</span>
            <code v-if="panel?.mappingFileName">{{ panel.mappingFileName }}</code>
            <span v-if="panel?.mappingError" class="mapping-error">{{ panel.mappingError }}</span>
          </div>
        </div>

        <div class="shortcut-action-list">
          <div v-if="groupedEntries.length === 0" class="native-empty-state">
            <strong>{{ settings.text('shortcuts.empty') }}</strong>
            <span>{{ settings.text('shortcuts.empty.help') }}</span>
          </div>

          <section v-for="group in groupedEntries" :key="group.category" class="shortcut-category">
            <button class="shortcut-category-header" type="button" @click="toggleCategory(group.category)">
              <span>{{ isExpanded(group.category) ? '⌄' : '›' }}</span>
              <strong>{{ categoryLabel(group.category) }}</strong>
              <small>{{ group.entries.length }}</small>
            </button>

            <template v-if="isExpanded(group.category)">
              <div class="shortcut-column-header">
                <span>{{ settings.text('shortcuts.column.function') }}</span>
                <span>{{ settings.text('shortcuts.column.rekordbox') }}</span>
                <span>{{ settings.text('shortcuts.column.input') }}</span>
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
                    <span v-if="entry.bindings.length === 0" class="shortcut-unassigned">
                      {{ settings.text('common.unassigned') }}
                    </span>
                    <template v-else>
                      <span v-for="binding in entry.bindings" :key="binding" class="shortcut-binding-chip">
                        {{ binding }}
                      </span>
                    </template>
                  </div>
                  <button
                    class="shortcut-row-action edit"
                    type="button"
                    :title="settings.text('shortcuts.edit.help')"
                    :disabled="shortcuts.isMutating || panel?.capture.isCapturing"
                    @click="learn(entry.id)"
                  >
                    {{ panel?.capture.entryID === entry.id ? '…' : '✎' }}
                  </button>
                  <button
                    class="shortcut-row-action remove"
                    type="button"
                    :title="settings.text('shortcuts.remove.help')"
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

    <div v-if="presetReorderOpen" class="shortcut-dialog-backdrop">
      <section class="preset-reorder-dialog" role="dialog" aria-modal="true">
        <div class="preset-reorder-heading">
          <div>
            <strong>{{ settings.text('preset.reorder') }}</strong>
            <span>{{ settings.text('preset.reorder.help') }}</span>
          </div>
          <button
            class="native-button"
            type="button"
            :disabled="isReorderingPresets"
            @click="presetReorderOpen = false"
          >
            {{ settings.text('common.close') }}
          </button>
        </div>

        <p v-if="presetReorderError" class="shortcut-panel-error" role="alert">{{ presetReorderError }}</p>

        <div ref="presetReorderElement" class="preset-reorder-list" :class="{ 'is-saving': isReorderingPresets }">
          <article
            v-for="preset in presets.items"
            :key="preset.id"
            class="native-list-row"
            :data-sortable-id="preset.id"
          >
            <button class="drag-handle" type="button" :aria-label="settings.text('preset.reorder')">⋮⋮</button>
            <span class="order-chip">{{ preset.order }}</span>
            <div class="row-main">
              <strong>{{ preset.name }}</strong>
              <span>{{ preset.rekordboxMode?.toUpperCase() ?? '—' }}</span>
            </div>
          </article>
        </div>
      </section>
    </div>
  </section>
</template>
