<script setup lang="ts">
import { useGroupPresetsStore } from '../stores/groupPresets'

const groupPresets = useGroupPresetsStore()
</script>

<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Rig configuration</p>
        <h1>Group Presets</h1>
      </div>
      <button class="primary-button" type="button" disabled>Add Group Preset</button>
    </div>

    <div class="list-card">
      <div v-if="groupPresets.items.length === 0" class="empty-state">No Group Presets loaded.</div>
      <article
        v-for="groupPreset in groupPresets.items"
        :key="groupPreset.id"
        class="list-row"
        :class="{ active: groupPreset.id === groupPresets.activeID }"
      >
        <span class="drag-handle" aria-hidden="true">⋮⋮</span>
        <span class="order-chip">{{ groupPreset.order }}</span>
        <div class="row-main">
          <strong>{{ groupPreset.name }}</strong>
          <span>{{ groupPreset.assignments.length }} device assignments</span>
        </div>
        <span v-if="groupPreset.id === groupPresets.activeID" class="active-badge">ACTIVE</span>
      </article>
    </div>
  </section>
</template>
