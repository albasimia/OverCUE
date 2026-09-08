<script setup lang="ts">
import { ref } from 'vue'
import { useSortableOrder } from '../composables/useSortableOrder'
import { usePresetsStore } from '../stores/presets'

const presets = usePresetsStore()
const listElement = ref<HTMLElement | null>(null)
const { isSaving, errorMessage } = useSortableOrder({
  element: listElement,
  currentIDs: () => presets.items.map((preset) => preset.id),
  persist: (ids) => presets.reorder(ids),
})
</script>

<template>
  <section class="standard-page">
    <div class="native-page-heading">
      <div class="native-page-title">
        <h1>Shortcuts</h1>
        <p>Preset order and shortcut configuration.</p>
        <p v-if="isSaving" class="page-status">Saving order…</p>
        <p v-else-if="errorMessage" class="page-status error" role="alert">{{ errorMessage }}</p>
      </div>
      <button class="native-button primary" type="button" disabled>Add Preset</button>
    </div>

    <div ref="listElement" class="native-list-card" :class="{ 'is-saving': isSaving }">
      <div v-if="presets.items.length === 0" class="native-empty-state">No Presets loaded.</div>
      <article
        v-for="preset in presets.items"
        :key="preset.id"
        class="native-list-row"
        :data-sortable-id="preset.id"
      >
        <button class="drag-handle" type="button" aria-label="Reorder Preset" title="Drag to reorder">⋮⋮</button>
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
