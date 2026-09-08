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
    <header class="topbar">
      <div class="brand">
        <div class="brand-mark">OC</div>
        <div>
          <strong>OverCUE</strong>
          <span>Controller Runtime</span>
        </div>
      </div>
      <div class="runtime-pill" :data-status="runtime.status.bridgeStatus">
        <span class="status-dot" />
        {{ runtime.status.bridgeStatus }}
      </div>
    </header>

    <div class="body-shell">
      <nav class="sidebar" aria-label="Main navigation">
        <RouterLink to="/">Dashboard</RouterLink>
        <RouterLink to="/presets">Presets</RouterLink>
        <RouterLink to="/group-presets">Group Presets</RouterLink>
        <RouterLink to="/devices">Devices</RouterLink>
        <RouterLink to="/settings">Settings</RouterLink>
      </nav>

      <main class="content">
        <div v-if="loadError" class="connection-banner" role="status">
          Local API is not connected yet: {{ loadError }}
        </div>
        <RouterView />
      </main>
    </div>
  </div>
</template>
