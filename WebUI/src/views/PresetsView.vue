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
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Mapping baseline</p>
        <h1>Presets</h1>
        <p v-if="isSaving" class="page-status">Saving order…</p>
        <p v-else-if="errorMessage" class="page-status error" role="alert">{{ errorMessage }}</p>
      </div>
      <button class="primary-button" type="button" disabled>Add Preset</button>
    </div>

    <div ref="listElement" class="list-card" :class="{ 'is-saving': isSaving }">
      <div v-if="presets.items.length === 0" class="empty-state">No Presets loaded.</div>
      <article
        v-for="preset in presets.items"
        :key="preset.id"
        class="list-row"
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
