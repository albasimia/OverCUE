<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import { useDevicesStore } from '../stores/devices'
import { useGroupPresetsStore } from '../stores/groupPresets'

const devices = useDevicesStore()
const groupPresets = useGroupPresetsStore()
const selectedID = ref<string | null>(null)

watchEffect(() => {
  if (!selectedID.value && devices.items.length > 0) {
    selectedID.value = devices.items[0].id
  }
})

const selectedDevice = computed(() =>
  devices.items.find((device) => device.id === selectedID.value) ?? devices.items[0] ?? null,
)

const activeGroupPresetName = computed(() =>
  groupPresets.items.find((preset) => preset.id === groupPresets.activeID)?.name ?? '—',
)
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

        <button class="native-button primary" type="button" disabled>＋ Add ACK05</button>
        <button class="native-button" type="button" disabled>＋ Add Generic HID</button>

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

          <div class="native-detail-card">
            <div class="detail-row">
              <span>Connection</span>
              <strong class="connection-value">
                <i class="device-dot" :class="{ online: selectedDevice.connected }" />
                {{ selectedDevice.connected ? 'Connected' : 'Disconnected' }}
              </strong>
            </div>
            <div class="detail-row">
              <span>Profile</span>
              <strong>{{ selectedDevice.profileName }}</strong>
            </div>
            <div class="detail-row vertical">
              <span>Logical Device ID</span>
              <code>{{ selectedDevice.id }}</code>
            </div>
          </div>
        </div>

        <div v-else class="native-empty-state detail-empty">
          <strong>Select a device</strong>
          <span>Device details will appear here.</span>
        </div>
      </div>
    </div>
  </section>
</template>
