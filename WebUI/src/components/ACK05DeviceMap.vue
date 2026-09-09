<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import type { ShortcutDialDirection, ShortcutDialState, ShortcutKeyState } from '../api/types'

const props = defineProps<{
  rotationQuarterTurns: number
  keys: ShortcutKeyState[]
  dial: ShortcutDialState[]
  unassignedLabel: string
}>()

const emit = defineEmits<{
  selectKey: [keyID: string]
  selectDial: [direction: ShortcutDialDirection]
}>()

const stageElement = ref<HTMLElement | null>(null)
const scale = ref(0.5)
let resizeObserver: ResizeObserver | null = null

const keyByID = computed(() =>
  Object.fromEntries(props.keys.map((key) => [key.id, key])),
)
const dialByDirection = computed(() =>
  Object.fromEntries(props.dial.map((dial) => [dial.direction, dial])),
)

const rotationStyle = computed(() => ({
  '--device-rotation': `${props.rotationQuarterTurns * 90}deg`,
  '--label-rotation': `${props.rotationQuarterTurns * -90}deg`,
}))

const canvasStyle = computed(() => ({
  transform: `translate(-50%, -50%) scale(${scale.value})`,
}))

const keyLayouts: Record<string, { left: number; top: number; width: number; height: number }> = {
  k1: { left: 316, top: 251, width: 84, height: 82 },
  k2: { left: 414, top: 251, width: 84, height: 82 },
  k3: { left: 512, top: 251, width: 84, height: 82 },
  k4: { left: 316, top: 347, width: 84, height: 82 },
  k5: { left: 414, top: 347, width: 84, height: 82 },
  k6: { left: 512, top: 347, width: 84, height: 82 },
  k7: { left: 610, top: 251, width: 84, height: 178 },
  k8: { left: 316, top: 445, width: 84, height: 82 },
  k9: { left: 414, top: 445, width: 182, height: 82 },
  k10: { left: 610, top: 445, width: 84, height: 82 },
}
const keyIDs = Object.keys(keyLayouts)

// This is the same enclosure math as ACK05BodyShape in the native SwiftUI UI.
const bodyPath = computed(() => {
  const canvasOffsetX = 20
  const canvasOffsetY = 165
  const width = 720
  const height = 430
  const left = canvasOffsetX + width * 0.075
  const top = canvasOffsetY + height * 0.10
  const right = canvasOffsetX + width * 0.99
  const bottom = canvasOffsetY + height * 0.92
  const cornerRadius = Math.min(width * 0.04, height * 0.06)
  const dialCenterX = canvasOffsetX + width / 2 - width * (222 / 720)
  const dialCenterY = canvasOffsetY + height / 2 - height * (72 / 430)
  const shoulderRadius = Math.min(width * (124 / 720), height * (124 / 430))
  const leftOffset = dialCenterX - left
  const leftIntersection = Math.sqrt(Math.max(0, shoulderRadius ** 2 - leftOffset ** 2))
  const shoulderStartX = left
  const shoulderStartY = dialCenterY + leftIntersection
  const topOffset = dialCenterY - top
  const topIntersection = Math.sqrt(Math.max(0, shoulderRadius ** 2 - topOffset ** 2))
  const shoulderEndX = dialCenterX + topIntersection
  const shoulderEndY = top

  return [
    `M ${shoulderEndX} ${shoulderEndY}`,
    `L ${right - cornerRadius} ${top}`,
    `Q ${right} ${top} ${right} ${top + cornerRadius}`,
    `L ${right} ${bottom - cornerRadius}`,
    `Q ${right} ${bottom} ${right - cornerRadius} ${bottom}`,
    `L ${left + cornerRadius} ${bottom}`,
    `Q ${left} ${bottom} ${left} ${bottom - cornerRadius}`,
    `L ${shoulderStartX} ${shoulderStartY}`,
    `A ${shoulderRadius} ${shoulderRadius} 0 0 1 ${shoulderEndX} ${shoulderEndY}`,
    'Z',
  ].join(' ')
})

function keyStyle(id: string) {
  const layout = keyLayouts[id]
  return {
    left: `${layout.left}px`,
    top: `${layout.top}px`,
    width: `${layout.width}px`,
    height: `${layout.height}px`,
  }
}

function updateScale() {
  const stage = stageElement.value
  if (!stage) return
  const width = Math.max(1, stage.clientWidth - 16)
  const height = Math.max(1, stage.clientHeight - 16)
  scale.value = Math.max(0.1, Math.min(1, width / 760, height / 760))
}

onMounted(() => {
  resizeObserver = new ResizeObserver(updateScale)
  if (stageElement.value) resizeObserver.observe(stageElement.value)
  updateScale()
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null
})
</script>

<template>
  <div ref="stageElement" class="ack05-map-stage">
    <div class="ack05-map-canvas" :style="canvasStyle">
      <div class="ack05-map-rotator" :style="rotationStyle">
        <svg class="ack05-map-body-svg" viewBox="0 0 760 760" aria-hidden="true">
          <path :d="bodyPath" class="ack05-map-body-shape" />
        </svg>

        <div class="ack05-map-dial">
          <div class="ack05-map-dial-center" />
          <button
            class="ack05-map-dial-zone left"
            :class="{
              active: dialByDirection.counterclockwise?.active,
              selected: dialByDirection.counterclockwise?.selected,
              highlighted: dialByDirection.counterclockwise?.highlighted,
            }"
            type="button"
            @click="emit('selectDial', 'counterclockwise')"
          >
            <span class="ack05-map-label dial-label">
              <b>←</b>
              <small>{{ dialByDirection.counterclockwise?.assignment?.functionName ?? unassignedLabel }}</small>
            </span>
          </button>
          <button
            class="ack05-map-dial-zone right"
            :class="{
              active: dialByDirection.clockwise?.active,
              selected: dialByDirection.clockwise?.selected,
              highlighted: dialByDirection.clockwise?.highlighted,
            }"
            type="button"
            @click="emit('selectDial', 'clockwise')"
          >
            <span class="ack05-map-label dial-label">
              <b>→</b>
              <small>{{ dialByDirection.clockwise?.assignment?.functionName ?? unassignedLabel }}</small>
            </span>
          </button>
        </div>

        <div class="ack05-map-side-mark" />

        <button
          v-for="id in keyIDs"
          :key="id"
          class="ack05-map-key"
          :class="{
            pressed: keyByID[id]?.pressed,
            selected: keyByID[id]?.selected,
            highlighted: keyByID[id]?.highlighted,
          }"
          :style="keyStyle(id)"
          type="button"
          @click="emit('selectKey', id)"
        >
          <span class="ack05-map-label key-label">
            <b>{{ id.toUpperCase() }}</b>
            <small v-if="keyByID[id]?.assignment">{{ keyByID[id]?.assignment?.functionName }}</small>
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
