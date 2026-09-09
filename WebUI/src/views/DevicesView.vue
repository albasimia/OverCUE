<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { DeviceKind } from '../api/types'
import { useDevicesStore } from '../stores/devices'
import { useGroupPresetsStore } from '../stores/groupPresets'

const devices = useDevicesStore()
const groupPresets = useGroupPresetsStore()
const selectedID = ref<string | null>(null)
const nameDraft = ref('')
const actionError = ref<string | null>(null)

const selectedDevice = computed(() =>
  devices.items.find((device) => device.id === selectedID.value) ?? devices.items[0] ?? null,
)

const activeGroupPresetName = computed(() =>
  groupPresets.items.find((preset) => preset.id === groupPresets.activeID)?.name ?? '—',
)

watch(
  () => devices.items,
  (items) => {
    if (!selectedID.value || !items.some((device) => device.id === selectedID.value)) {
      selectedID.value = items[0]?.id ?? null
    }
  },
  { immediate: true, deep: true },
)

watch(
  () => selectedDevice.value,
  (device) => {
    nameDraft.value = device?.name ?? ''
    actionError.value = null
  },
  { immediate: true },
)

async function perform(action: () => Promise<unknown>) {
  actionError.value = null
  try {
    await action()
  } catch (error) {
    actionError.value = error instanceof Error ? error.message : String(error)
  }
}

function beginAdd(kind: DeviceKind) {
  void perform(() => devices.beginAdd(kind))
}

function beginRebind(kind?: DeviceKind) {
  const device = selectedDevice.value
  if (!device) return
  void perform(() => devices.beginRebind(device.id, kind))
}

function saveName() {
  const device = selectedDevice.value
  const name = nameDraft.value.trim()
  if (!device || !name) return
  void perform(() => devices.rename(device.id, name))
}

function setProfile(event: Event) {
  const device = selectedDevice.value
  const profileName = (event.target as HTMLSelectElement).value
  if (!device || !profileName || profileName === device.profileName) return
  void perform(() => devices.assignProfile(device.id, profileName))
}

function forgetBinding() {
  const device = selectedDevice.value
  if (!device) return
  void perform(() => devices.forgetBinding(device.id))
}

function hardwareLabel(kind: DeviceKind | undefined) {
  if (kind === 'ack05') return 'ACK05'
  if (kind === 'genericHID') return 'Generic HID'
  return 'Not bound'
}

onMounted(() => devices.resumeIdentifyPolling())

onBeforeUnmount(() => {
  if (devices.isIdentifying) {
    void devices.cancelIdentify().catch(() => {})
  } else {
    devices.stopIdentifyPolling()
  }
})
</script>

<template>
  <section class="device-page">
    <div class="device-split">
      <aside class="device-list-pane">
        <div class="native-page-title compact">
          <h1>Devices</h1>
          <p>Manage logical controller devices.</p>
        </div>

        <div class="native-selector-row">
          <span>Group Preset</span>
          <strong>{{ activeGroupPresetName }}</strong>
        </div>

        <div class="native-divider" />

        <button
          class="native-button primary"
          type="button"
          :disabled="devices.isMutating || devices.isIdentifying"
          @click="beginAdd('ack05')"
        >
          ＋ Add ACK05
        </button>
        <button
          class="native-button"
          type="button"
          :disabled="devices.isMutating || devices.isIdentifying"
          @click="beginAdd('genericHID')"
        >
          ＋ Add Generic HID
        </button>

        <div v-if="devices.items.length === 0" class="native-empty-state">
          <div class="empty-icon">⌘</div>
          <strong>No devices loaded.</strong>
          <span>Registered logical devices will appear here.</span>
        </div>

        <div v-else class="device-list">
          <button
            v-for="device in devices.items"
            :key="device.id"
            class="device-list-row"
            :class="{ selected: selectedDevice?.id === device.id }"
            type="button"
            @click="selectedID = device.id"
          >
            <span class="device-icon">◉</span>
            <span class="device-row-copy">
              <strong>{{ device.name }}</strong>
              <span>
                <i class="device-dot" :class="{ online: device.connected }" />
                {{ device.connected ? 'Connected' : 'Disconnected' }}
              </span>
            </span>
            <span class="chevron">›</span>
          </button>
        </div>
      </aside>

      <div class="device-detail-pane">
        <div v-if="selectedDevice" class="device-detail-content">
          <div class="native-page-title">
            <h1>{{ selectedDevice.name }}</h1>
            <p>Logical Device</p>
          </div>

          <div v-if="devices.isIdentifying" class="device-identify-panel">
            <div>
              <strong>Identify device</strong>
              <span>
                Waiting for {{ devices.management.identifyKind === 'genericHID' ? 'Generic HID' : 'ACK05' }} input ·
                {{ devices.management.identifyCandidateCount }} candidates
              </span>
            </div>
            <button class="native-button" type="button" @click="perform(() => devices.cancelIdentify())">
              Cancel
            </button>
          </div>

          <div class="native-detail-card">
            <div class="detail-row">
              <span>Connection</span>
              <strong class="connection-value">
                <i class="device-dot" :class="{ online: selectedDevice.connected }" />
                {{ selectedDevice.connected ? 'Connected' : 'Disconnected' }}
              </strong>
            </div>
            <div class="detail-row">
              <span>Hardware</span>
              <strong>{{ hardwareLabel(selectedDevice.binding?.kind) }}</strong>
            </div>
            <div class="detail-row">
              <span>Profile</span>
              <strong>{{ selectedDevice.profileName }}</strong>
            </div>
            <div class="detail-row vertical">
              <span>Logical Device ID</span>
              <code>{{ selectedDevice.id }}</code>
            </div>
            <div class="detail-row vertical">
              <span>Binding Identifier</span>
              <code>{{ selectedDevice.binding?.bindingIdentifier ?? 'Not bound' }}</code>
            </div>
          </div>

          <div class="native-detail-card device-settings-card">
            <div class="device-form-row">
              <label for="device-name">Name</label>
              <input id="device-name" v-model="nameDraft" class="native-input" type="text" />
              <button
                class="native-button"
                type="button"
                :disabled="!nameDraft.trim() || devices.isMutating"
                @click="saveName"
              >
                Save
              </button>
            </div>

            <div class="device-form-row">
              <label for="device-profile">Profile</label>
              <select
                id="device-profile"
                class="native-select"
                :value="selectedDevice.profileName"
                :disabled="devices.isMutating"
                @change="setProfile"
              >
                <option v-for="profile in devices.profileNames" :key="profile" :value="profile">
                  {{ profile }}
                </option>
              </select>
            </div>
          </div>

          <div class="native-detail-card">
            <div class="binding-copy">
              <strong>Physical Device Binding</strong>
              <span v-if="selectedDevice.binding">Re-identify the controller or forget the current binding.</span>
              <span v-else>Identify a physical controller for this Logical Device.</span>
            </div>

            <div class="device-actions">
              <template v-if="selectedDevice.binding">
                <button
                  class="native-button primary"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind()"
                >
                  Rebind
                </button>
                <button
                  class="native-button danger"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="forgetBinding"
                >
                  Forget Binding
                </button>
              </template>
              <template v-else>
                <button
                  class="native-button primary"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind('ack05')"
                >
                  Identify ACK05
                </button>
                <button
                  class="native-button"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind('genericHID')"
                >
                  Identify Generic HID
                </button>
              </template>
            </div>
          </div>

          <p v-if="devices.management.statusMessage" class="device-status success">
            {{ devices.management.statusMessage }}
          </p>
          <p v-if="actionError || devices.management.errorMessage || devices.errorMessage" class="device-status error">
            {{ actionError ?? devices.management.errorMessage ?? devices.errorMessage }}
          </p>
        </div>

        <div v-else class="native-empty-state detail-empty">
          <strong>Select a device</strong>
          <span>Device details will appear here.</span>
        </div>
      </div>
    </div>
  </section>
</template>
