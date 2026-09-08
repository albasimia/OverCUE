<script setup lang="ts">
import { ref } from 'vue'
import { useSortableOrder } from '../composables/useSortableOrder'
import { useGroupPresetsStore } from '../stores/groupPresets'

const groupPresets = useGroupPresetsStore()
const listElement = ref<HTMLElement | null>(null)
const { isSaving, errorMessage } = useSortableOrder({
  element: listElement,
  currentIDs: () => groupPresets.items.map((groupPreset) => groupPreset.id),
  persist: (ids) => groupPresets.reorder(ids),
})
</script>

<template>
  <section class="standard-page">
    <div class="native-page-heading">
      <div class="native-page-title">
        <h1>Group Presets</h1>
        <p>Assign Presets to the devices used together in one rig.</p>
        <p v-if="isSaving" class="page-status">Saving order…</p>
        <p v-else-if="errorMessage" class="page-status error" role="alert">{{ errorMessage }}</p>
      </div>
      <button class="native-button primary" type="button" disabled>Add Group Preset</button>
    </div>

    <div ref="listElement" class="native-list-card" :class="{ 'is-saving': isSaving }">
      <div v-if="groupPresets.items.length === 0" class="native-empty-state">No Group Presets loaded.</div>
      <article
        v-for="groupPreset in groupPresets.items"
        :key="groupPreset.id"
        class="native-list-row"
        :class="{ active: groupPreset.id === groupPresets.activeID }"
        :data-sortable-id="groupPreset.id"
      >
        <button class="drag-handle" type="button" aria-label="Reorder Group Preset" title="Drag to reorder">⋮⋮</button>
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
