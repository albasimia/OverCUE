<script setup lang="ts">
import { useDevicesStore } from '../stores/devices'
import { useGroupPresetsStore } from '../stores/groupPresets'
import { usePresetsStore } from '../stores/presets'
import { useRuntimeStore } from '../stores/runtime'

const presets = usePresetsStore()
const groupPresets = useGroupPresetsStore()
const devices = useDevicesStore()
const runtime = useRuntimeStore()
</script>

<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Runtime overview</p>
        <h1>Dashboard</h1>
      </div>
    </div>

    <div class="stat-grid">
      <article class="card stat-card">
        <span>Active Group Preset</span>
        <strong>{{ groupPresets.active?.name ?? '—' }}</strong>
      </article>
      <article class="card stat-card">
        <span>Presets</span>
        <strong>{{ presets.items.length }}</strong>
      </article>
      <article class="card stat-card">
        <span>Devices</span>
        <strong>{{ devices.items.length }}</strong>
      </article>
      <article class="card stat-card">
        <span>Controller Input</span>
        <strong>{{ runtime.status.inputEnabled ? 'ON' : 'OFF' }}</strong>
      </article>
    </div>
  </section>
</template>
