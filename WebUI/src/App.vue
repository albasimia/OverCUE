<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import { overcueAPI } from './api/client'
import { useDevicesStore } from './stores/devices'
import { useGroupPresetsStore } from './stores/groupPresets'
import { usePresetsStore } from './stores/presets'
import { useRuntimeStore } from './stores/runtime'
import { useSettingsStore } from './stores/settings'

const presets = usePresetsStore()
const groupPresets = useGroupPresetsStore()
const devices = useDevicesStore()
const runtime = useRuntimeStore()
const settings = useSettingsStore()
const loadError = ref<string | null>(null)

const bridgeStatusText = computed(() => {
  const status = runtime.status.bridgeStatus
  if (status === 'degraded' || status === 'failed') {
    return settings.text(`app.status.${status}`, '').replace(/[:：]\s*$/, '')
  }
  return settings.text(`app.status.${status}`)
})

async function loadSnapshot() {
  try {
    const snapshot = await overcueAPI.snapshot()
    presets.replace(snapshot.presets)
    groupPresets.replace(snapshot.groupPresets, snapshot.runtime.activeGroupPresetID)
    devices.replace(snapshot.devices, snapshot.profileNames, snapshot.deviceManagement)
    runtime.replace(snapshot.runtime)
    loadError.value = null
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : String(error)
  }
}

function handleActiveGroupPresetChanged(event: Event) {
  const detail = (event as CustomEvent<{ activeGroupPresetID?: string | null }>).detail
  if (!detail || !Object.prototype.hasOwnProperty.call(detail, 'activeGroupPresetID')) return
  groupPresets.setActiveID(detail.activeGroupPresetID ?? null)
}

onMounted(() => {
  window.addEventListener('overcue:active-group-preset-changed', handleActiveGroupPresetChanged)
  void Promise.all([loadSnapshot(), settings.load()])
})

onUnmounted(() => {
  window.removeEventListener('overcue:active-group-preset-changed', handleActiveGroupPresetChanged)
})
</script>

<template>
  <div class="app-shell">
    <header class="application-header">
      <div class="brand">
        <img class="brand-mark" src="/OverCUEIcon.png" alt="" aria-hidden="true" />
        <strong>OverCUE</strong>
      </div>

      <nav class="section-picker" :aria-label="settings.text('nav.shortcuts')">
        <RouterLink to="/shortcuts">{{ settings.text('nav.shortcuts') }}</RouterLink>
        <RouterLink to="/devices">{{ settings.text('nav.devices') }}</RouterLink>
        <RouterLink to="/group-presets">{{ settings.text('groupPreset.title') }}</RouterLink>
        <RouterLink to="/settings">{{ settings.text('nav.settings') }}</RouterLink>
      </nav>

      <div class="runtime-status" :data-status="runtime.status.bridgeStatus">
        <span class="status-dot" />
        <span>{{ bridgeStatusText }}</span>
      </div>
    </header>

    <main class="content-shell">
      <div v-if="loadError" class="connection-banner" role="status">
        {{ settings.text('app.localAPI') }}: {{ loadError }}
      </div>
      <RouterView />
    </main>
  </div>
</template>
