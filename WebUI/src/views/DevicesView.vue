<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { DeviceKind } from '../api/types'
import { useDevicesStore } from '../stores/devices'
import { useGroupPresetsStore } from '../stores/groupPresets'
import { useSettingsStore } from '../stores/settings'

const devices = useDevicesStore()
const groupPresets = useGroupPresetsStore()
const settings = useSettingsStore()
const selectedID = ref<string | null>(null)
const nameDraft = ref('')
const actionError = ref<string | null>(null)
const confirmForget = ref(false)

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
    confirmForget.value = false
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
  confirmForget.value = false
  void perform(() => devices.beginAdd(kind))
}

function beginRebind(kind?: DeviceKind) {
  const device = selectedDevice.value
  if (!device) return
  confirmForget.value = false
  void perform(() => devices.beginRebind(device.id, kind))
}

function cancelIdentify() {
  void perform(() => devices.cancelIdentify())
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
  if (!confirmForget.value) {
    confirmForget.value = true
    return
  }
  confirmForget.value = false
  void perform(() => devices.forgetBinding(device.id))
}

function hardwareLabel(kind: DeviceKind | undefined) {
  if (kind === 'ack05') return 'ACK05'
  if (kind === 'genericHID') return 'Generic HID'
  return settings.text('devices.binding.none')
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
          <h1>{{ settings.text('devices.title') }}</h1>
          <p>{{ settings.text('devices.subtitle') }}</p>
        </div>

        <div class="native-selector-row">
          <span>{{ settings.text('groupPreset.title') }}</span>
          <strong>{{ activeGroupPresetName }}</strong>
        </div>

        <div class="native-divider" />

        <button
          class="native-button primary"
          type="button"
          :disabled="devices.isMutating || devices.isIdentifying"
          @click="beginAdd('ack05')"
        >
          ＋ {{ settings.text('devices.addAck05') }}
        </button>
        <button
          class="native-button"
          type="button"
          :disabled="devices.isMutating || devices.isIdentifying"
          @click="beginAdd('genericHID')"
        >
          ＋ {{ settings.text('devices.addGeneric') }}
        </button>

        <div v-if="devices.isIdentifying" class="device-identify-panel compact">
          <div>
            <strong>{{ settings.text('devices.identify.title') }}</strong>
            <span>
              {{ settings.text('devices.identify.prompt') }} ·
              {{ settings.text('devices.identify.candidates', devices.management.identifyCandidateCount) }}
            </span>
          </div>
          <button class="native-button" type="button" @click="cancelIdentify">{{ settings.text('common.cancel') }}</button>
        </div>

        <p v-if="actionError || devices.management.errorMessage || devices.errorMessage" class="device-status error">
          {{ actionError ?? devices.management.errorMessage ?? devices.errorMessage }}
        </p>

        <div v-if="devices.items.length === 0" class="native-empty-state">
          <div class="empty-icon">⌘</div>
          <strong>{{ settings.text('devices.empty') }}</strong>
          <span>{{ settings.text('devices.empty.help') }}</span>
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
                {{ settings.text(device.connected ? 'devices.connected' : 'devices.disconnected') }}
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
            <p>{{ settings.text('devices.logicalDevice') }}</p>
          </div>

          <div class="native-detail-card">
            <div class="detail-row">
              <span>{{ settings.text('devices.connection') }}</span>
              <strong class="connection-value">
                <i class="device-dot" :class="{ online: selectedDevice.connected }" />
                {{ settings.text(selectedDevice.connected ? 'devices.connected' : 'devices.disconnected') }}
              </strong>
            </div>
            <div class="detail-row">
              <span>{{ settings.text('devices.hardware') }}</span>
              <strong>{{ hardwareLabel(selectedDevice.binding?.kind) }}</strong>
            </div>
            <div class="detail-row">
              <span>{{ settings.text('devices.profile') }}</span>
              <strong>{{ selectedDevice.profileName }}</strong>
            </div>
            <div class="detail-row vertical">
              <span>{{ settings.text('devices.logicalId') }}</span>
              <code>{{ selectedDevice.id }}</code>
            </div>
            <div class="detail-row vertical">
              <span>{{ settings.text('devices.pairingId') }}</span>
              <code>{{ selectedDevice.binding?.bindingIdentifier ?? settings.text('devices.binding.none') }}</code>
            </div>
          </div>

          <div class="native-detail-card device-settings-card">
            <div class="device-form-row">
              <label for="device-name">{{ settings.text('devices.name') }}</label>
              <input id="device-name" v-model="nameDraft" class="native-input" type="text" />
              <button
                class="native-button"
                type="button"
                :disabled="!nameDraft.trim() || devices.isMutating"
                @click="saveName"
              >
                {{ settings.text('common.save') }}
              </button>
            </div>

            <div class="device-form-row">
              <label for="device-profile">{{ settings.text('devices.profile') }}</label>
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
              <strong>{{ settings.text('devices.section.binding') }}</strong>
              <span v-if="selectedDevice.binding">{{ settings.text('devices.binding.ok.help') }}</span>
              <span v-else>{{ settings.text('devices.binding.missing.help') }}</span>
            </div>

            <div class="device-actions">
              <template v-if="selectedDevice.binding">
                <button
                  class="native-button primary"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind()"
                >
                  {{ settings.text('devices.rebind.action') }}
                </button>
                <button
                  class="native-button danger"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="forgetBinding"
                >
                  {{ confirmForget ? settings.text('devices.forget.title') : settings.text('devices.forget.action') }}
                </button>
                <button
                  v-if="confirmForget"
                  class="native-button"
                  type="button"
                  @click="confirmForget = false"
                >
                  {{ settings.text('common.cancel') }}
                </button>
              </template>
              <template v-else>
                <button
                  class="native-button primary"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind('ack05')"
                >
                  {{ settings.text('devices.identify.ack05.action') }}
                </button>
                <button
                  class="native-button"
                  type="button"
                  :disabled="devices.isMutating || devices.isIdentifying"
                  @click="beginRebind('genericHID')"
                >
                  {{ settings.text('devices.identify.generic.action') }}
                </button>
              </template>
            </div>
          </div>

          <p v-if="devices.management.statusMessage" class="device-status success">
            {{ devices.management.statusMessage }}
          </p>
        </div>

        <div v-else class="native-empty-state detail-empty">
          <strong>{{ settings.text('devices.select') }}</strong>
        </div>
      </div>
    </div>
  </section>
</template>
