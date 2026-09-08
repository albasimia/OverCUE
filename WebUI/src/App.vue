<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import { overcueAPI } from './api/client'
import { useDevicesStore } from './stores/devices'
import { useGroupPresetsStore } from './stores/groupPresets'
import { usePresetsStore } from './stores/presets'
import { useRuntimeStore } from './stores/runtime'

const presets = usePresetsStore()
const groupPresets = useGroupPresetsStore()
const devices = useDevicesStore()
const runtime = useRuntimeStore()
const loadError = ref<string | null>(null)

async function loadSnapshot() {
  try {
    const snapshot = await overcueAPI.snapshot()
    presets.replace(snapshot.presets)
    groupPresets.replace(snapshot.groupPresets, snapshot.runtime.activeGroupPresetID)
    devices.replace(snapshot.devices)
    runtime.replace(snapshot.runtime)
    loadError.value = null
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : String(error)
  }
}

onMounted(loadSnapshot)
</script>

<template>
  <div class="app-shell">
    <header class="application-header">
      <div class="brand">
        <div class="brand-mark" aria-hidden="true">OC</div>
        <strong>OverCUE</strong>
      </div>

      <nav class="section-picker" aria-label="Main navigation">
        <RouterLink to="/presets">Shortcuts</RouterLink>
        <RouterLink to="/devices">Devices</RouterLink>
        <RouterLink to="/group-presets">Group Presets</RouterLink>
        <RouterLink to="/settings">Settings</RouterLink>
      </nav>

      <div class="runtime-status" :data-status="runtime.status.bridgeStatus">
        <span class="status-dot" />
        <span>{{ runtime.status.bridgeStatus }}</span>
      </div>
    </header>

    <main class="content-shell">
      <div v-if="loadError" class="connection-banner" role="status">
        Local API is not connected yet: {{ loadError }}
      </div>
      <RouterView />
    </main>
  </div>
</template>
