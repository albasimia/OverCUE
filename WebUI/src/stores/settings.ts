import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useSettingsStore = defineStore('settings', () => {
  const language = ref<'ja' | 'en' | 'zh-Hans'>('ja')
  return { language }
})
