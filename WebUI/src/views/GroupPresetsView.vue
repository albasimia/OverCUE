<script setup lang="ts">
import { computed, ref } from 'vue'
import type { DeviceSummary, GroupPresetSummary } from '../api/types'
import { useSortableOrder } from '../composables/useSortableOrder'
import { useDevicesStore } from '../stores/devices'
import { useGroupPresetsStore } from '../stores/groupPresets'

const groupPresets = useGroupPresetsStore()
const devices = useDevicesStore()
const listElement = ref<HTMLElement | null>(null)
const operationError = ref<string | null>(null)
const editorMode = ref<'add' | 'rename' | null>(null)
const editorTargetID = ref<string | null>(null)
const editorName = ref('')
const confirmDeleteID = ref<string | null>(null)

const { isSaving, errorMessage } = useSortableOrder({
  element: listElement,
  currentIDs: () => groupPresets.items.map((groupPreset) => groupPreset.id),
  persist: (ids) => groupPresets.reorder(ids),
})

const activeAssignments = computed(() =>
  new Map(
    (groupPresets.active?.assignments ?? []).map((assignment) => [
      assignment.logicalDeviceID,
      assignment.presetID,
    ]),
  ),
)

async function perform(action: () => Promise<unknown>) {
  operationError.value = null
  try {
    await action()
  } catch (error) {
    operationError.value = error instanceof Error ? error.message : String(error)
  }
}

function beginAdd() {
  editorMode.value = 'add'
  editorTargetID.value = null
  editorName.value = `Group Preset ${groupPresets.items.length + 1}`
  operationError.value = null
  confirmDeleteID.value = null
}

function beginRename(groupPreset: GroupPresetSummary) {
  editorMode.value = 'rename'
  editorTargetID.value = groupPreset.id
  editorName.value = groupPreset.name
  operationError.value = null
  confirmDeleteID.value = null
}

function cancelEditor() {
  editorMode.value = null
  editorTargetID.value = null
  editorName.value = ''
}

async function saveEditor() {
  const name = editorName.value.trim()
  if (!name) return

  if (editorMode.value === 'add') {
    await perform(() => groupPresets.add(name))
    if (!operationError.value) cancelEditor()
    return
  }

  if (editorMode.value === 'rename' && editorTargetID.value) {
    await perform(() => groupPresets.rename(editorTargetID.value!, name))
    if (!operationError.value) cancelEditor()
  }
}

function activate(id: string) {
  confirmDeleteID.value = null
  void perform(() => groupPresets.activate(id))
}

function requestDelete(id: string) {
  if (confirmDeleteID.value !== id) {
    confirmDeleteID.value = id
    return
  }
  confirmDeleteID.value = null
  void perform(() => groupPresets.remove(id))
}

function isIncluded(device: DeviceSummary) {
  return activeAssignments.value.has(device.id)
}

function assignedPresetID(device: DeviceSummary) {
  return activeAssignments.value.get(device.id) ?? device.presets[0]?.id ?? ''
}

function setIncluded(device: DeviceSummary, event: Event) {
  const groupPreset = groupPresets.active
  if (!groupPreset) return
  const included = (event.target as HTMLInputElement).checked
  void perform(() => groupPresets.setIncluded(groupPreset.id, device.id, included))
}

function assignPreset(device: DeviceSummary, event: Event) {
  const groupPreset = groupPresets.active
  if (!groupPreset) return
  const presetID = (event.target as HTMLSelectElement).value
  if (!presetID) return
  void perform(() => groupPresets.assignPreset(groupPreset.id, device.id, presetID))
}
</script>

<template>
  <section class="standard-page group-presets-page">
    <div class="native-page-heading">
      <div class="native-page-title">
        <h1>Group Presets</h1>
        <p>Assign Presets to the devices used together in one rig.</p>
        <p v-if="isSaving" class="page-status">Saving order…</p>
        <p v-else-if="errorMessage || operationError" class="page-status error" role="alert">
          {{ errorMessage ?? operationError }}
        </p>
      </div>
      <button class="native-button primary" type="button" @click="beginAdd">Add Group Preset</button>
    </div>

    <div v-if="editorMode" class="group-preset-editor native-detail-card">
      <div>
        <strong>{{ editorMode === 'add' ? 'Add Group Preset' : 'Rename Group Preset' }}</strong>
        <span>Group Preset names are used in the menu bar and rig selector.</span>
      </div>
      <input v-model="editorName" class="native-input" type="text" @keyup.enter="saveEditor" />
      <div class="device-actions">
        <button class="native-button" type="button" @click="cancelEditor">Cancel</button>
        <button class="native-button primary" type="button" :disabled="!editorName.trim()" @click="saveEditor">
          Save
        </button>
      </div>
    </div>

    <div ref="listElement" class="native-list-card group-preset-list" :class="{ 'is-saving': isSaving }">
      <div v-if="groupPresets.items.length === 0" class="native-empty-state">No Group Presets loaded.</div>
      <article
        v-for="groupPreset in groupPresets.items"
        :key="groupPreset.id"
        class="native-list-row group-preset-row"
        :class="{ active: groupPreset.id === groupPresets.activeID }"
        :data-sortable-id="groupPreset.id"
      >
        <button class="drag-handle" type="button" aria-label="Reorder Group Preset" title="Drag to reorder">⋮⋮</button>
        <span class="order-chip">{{ groupPreset.order }}</span>
        <button class="group-preset-main" type="button" @click="activate(groupPreset.id)">
          <span class="row-main">
            <strong>{{ groupPreset.name }}</strong>
            <span>{{ groupPreset.assignments.length }} device assignments</span>
          </span>
        </button>
        <span v-if="groupPreset.id === groupPresets.activeID" class="active-badge">ACTIVE</span>
        <button v-else class="native-button compact" type="button" @click="activate(groupPreset.id)">Activate</button>
        <button class="native-button compact" type="button" @click="beginRename(groupPreset)">Rename</button>
        <button
          class="native-button compact danger"
          type="button"
          :disabled="groupPresets.items.length <= 1"
          @click="requestDelete(groupPreset.id)"
        >
          {{ confirmDeleteID === groupPreset.id ? 'Confirm Delete' : 'Delete' }}
        </button>
        <button
          v-if="confirmDeleteID === groupPreset.id"
          class="native-button compact"
          type="button"
          @click="confirmDeleteID = null"
        >
          Cancel
        </button>
      </article>
    </div>

    <div class="native-divider group-assignment-divider" />

    <section class="group-assignment-section">
      <div class="native-page-title compact">
        <h2>{{ groupPresets.active?.name ?? 'No Active Group Preset' }}</h2>
        <p>Choose which Logical Devices participate and which Preset each one starts on.</p>
      </div>

      <div v-if="devices.items.length === 0" class="native-empty-state assignment-empty">
        <strong>No Logical Devices</strong>
        <span>Add a device first, then assign it to this Group Preset.</span>
      </div>

      <div v-else class="group-assignment-table">
        <div class="group-assignment-header">
          <span>Logical Device</span>
          <span>Include</span>
          <span>Preset</span>
        </div>

        <article v-for="device in devices.items" :key="device.id" class="group-assignment-row">
          <div class="assignment-device-copy">
            <strong>{{ device.name }}</strong>
            <span>
              <i class="device-dot" :class="{ online: device.connected }" />
              {{ device.profileName }} · {{ device.connected ? 'Connected' : 'Disconnected' }}
            </span>
          </div>

          <label class="native-switch">
            <input
              type="checkbox"
              :checked="isIncluded(device)"
              :disabled="!groupPresets.active"
              @change="setIncluded(device, $event)"
            />
            <span aria-hidden="true" />
          </label>

          <select
            class="native-select"
            :value="assignedPresetID(device)"
            :disabled="!isIncluded(device) || device.presets.length === 0"
            @change="assignPreset(device, $event)"
          >
            <option v-for="preset in device.presets" :key="preset.id" :value="preset.id">
              {{ preset.name }}
            </option>
          </select>
        </article>
      </div>
    </section>
  </section>
</template>
