<script setup lang="ts">
import { usePresetsStore } from '../stores/presets'

const presets = usePresetsStore()
</script>

<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Mapping baseline</p>
        <h1>Presets</h1>
      </div>
      <button class="primary-button" type="button" disabled>Add Preset</button>
    </div>

    <div class="list-card">
      <div v-if="presets.items.length === 0" class="empty-state">No Presets loaded.</div>
      <article v-for="preset in presets.items" :key="preset.id" class="list-row">
        <span class="drag-handle" aria-hidden="true">⋮⋮</span>
        <span class="order-chip">{{ preset.order }}</span>
        <div class="row-main">
          <strong>{{ preset.name }}</strong>
          <span>{{ preset.profileName }} · {{ preset.rekordboxMode ?? 'mode unset' }}</span>
        </div>
        <code>{{ preset.id }}</code>
      </article>
    </div>
  </section>
</template>
