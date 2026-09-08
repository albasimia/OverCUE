import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { RuntimeStatus } from '../api/types'

const initialStatus: RuntimeStatus = {
  inputEnabled: false,
  bridgeStatus: 'stopped',
  activeGroupPresetID: null,
}

export const useRuntimeStore = defineStore('runtime', () => {
  const status = ref<RuntimeStatus>(initialStatus)
  const isConnected = computed(() => status.value.bridgeStatus === 'running')

  function replace(next: RuntimeStatus) {
    status.value = next
  }

  return { status, isConnected, replace }
})
