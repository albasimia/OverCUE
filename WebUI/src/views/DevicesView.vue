<script setup lang="ts">
import { useDevicesStore } from '../stores/devices'

const devices = useDevicesStore()
</script>

<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Physical → Logical</p>
        <h1>Devices</h1>
      </div>
    </div>

    <div class="list-card">
      <div v-if="devices.items.length === 0" class="empty-state">No devices loaded.</div>
      <article v-for="device in devices.items" :key="device.id" class="list-row">
        <span class="device-dot" :class="{ online: device.connected }" />
        <div class="row-main">
          <strong>{{ device.name }}</strong>
          <span>{{ device.profileName }}</span>
        </div>
        <code>{{ device.id }}</code>
      </article>
    </div>
  </section>
</template>
