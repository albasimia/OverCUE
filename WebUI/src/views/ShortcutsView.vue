<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted } from 'vue'
import { useShortcutsStore } from '../stores/shortcuts'

const shortcuts = useShortcutsStore()

onMounted(() => {
  void shortcuts.startPolling()
})

onBeforeUnmount(() => {
  shortcuts.stopPolling()
})

const panel = computed(() => shortcuts.panel)
const keyByID = computed(() =>
  Object.fromEntries((panel.value?.keys ?? []).map((key) => [key.id, key])),
)
const dialByDirection = computed(() =>
  Object.fromEntries((panel.value?.dial ?? []).map((dial) => [dial.direction, dial])),
)

const mapStyle = computed(() => ({
  '--device-rotation': `${(panel.value?.rotationQuarterTurns ?? 0) * 90}deg`,
  '--label-rotation': `${(panel.value?.rotationQuarterTurns ?? 0) * -90}deg`,
}))

const assignmentRows = computed(() => {
  const keyRows = (panel.value?.keys ?? []).map((key) => ({
    id: key.id,
    label: key.id.toUpperCase(),
    functionName: key.assignment?.functionName ?? 'Unassigned',
    shortcut: key.assignment?.shortcut ?? '',
    active: key.pressed,
  }))
  const dialRows = (panel.value?.dial ?? []).map((dial) => ({
    id: `dial-${dial.direction}`,
    label: dial.direction === 'clockwise' ? 'DIAL →' : 'DIAL ←',
    functionName: dial.assignment?.functionName ?? 'Unassigned',
    shortcut: dial.assignment?.shortcut ?? '',
    active: dial.active,
  }))
  return [...keyRows, ...dialRows]
})
</script>

<template>
  <section class="shortcuts-page">
    <div class="shortcuts-split">
      <aside class="shortcut-device-pane">
        <div class="shortcut-device-header">
          <div>
            <h2>{{ panel?.deviceName ?? 'ACK05' }}</h2>
            <p>Device Map</p>
          </div>
        </div>

        <div class="shortcut-preset-row">
          <span>Preset</span>
          <strong>{{ panel?.presetName ?? '—' }}</strong>
        </div>

        <div v-if="shortcuts.errorMessage" class="shortcut-panel-error" role="alert">
          {{ shortcuts.errorMessage }}
        </div>

        <div class="ack05-stage">
          <div class="ack05-rotator" :style="mapStyle">
            <div class="ack05-body">
              <div class="ack05-dial">
                <div class="dial-center" />
                <div
                  class="dial-zone dial-zone-left"
                  :class="{ active: dialByDirection.counterclockwise?.active }"
                >
                  <span class="dial-copy">
                    <b>←</b>
                    <small>{{ dialByDirection.counterclockwise?.assignment?.functionName ?? 'Unassigned' }}</small>
                  </span>
                </div>
                <div
                  class="dial-zone dial-zone-right"
                  :class="{ active: dialByDirection.clockwise?.active }"
                >
                  <span class="dial-copy">
                    <b>→</b>
                    <small>{{ dialByDirection.clockwise?.assignment?.functionName ?? 'Unassigned' }}</small>
                  </span>
                </div>
              </div>

              <div class="ack05-side-mark" />

              <button
                v-for="id in ['k1','k2','k3','k4','k5','k6','k7','k8','k9','k10']"
                :key="id"
                class="ack05-key"
                :class="[id, { pressed: keyByID[id]?.pressed }]"
                type="button"
                tabindex="-1"
              >
                <span class="key-copy">
                  <b>{{ id.toUpperCase() }}</b>
                  <small v-if="keyByID[id]?.assignment">{{ keyByID[id]?.assignment?.functionName }}</small>
                </span>
              </button>
            </div>
          </div>
        </div>

        <div class="pressed-readout">
          <span>Input</span>
          <strong>
            {{ assignmentRows.filter((row) => row.active).map((row) => row.label).join(' + ') || '—' }}
          </strong>
        </div>
      </aside>

      <div class="shortcut-list-pane">
        <div class="native-page-title shortcut-list-title">
          <h1>Shortcuts</h1>
          <p>Current device assignments</p>
        </div>

        <div class="shortcut-assignment-list">
          <article
            v-for="row in assignmentRows"
            :key="row.id"
            class="shortcut-assignment-row"
            :class="{ active: row.active }"
          >
            <span class="binding-chip">{{ row.label }}</span>
            <div class="assignment-copy">
              <strong>{{ row.functionName }}</strong>
              <span>{{ row.shortcut || 'No rekordbox shortcut' }}</span>
            </div>
          </article>
        </div>
      </div>
    </div>
  </section>
</template>
