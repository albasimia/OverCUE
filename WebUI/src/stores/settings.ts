import { defineStore } from 'pinia'
import { ref } from 'vue'
import { overcueAPI } from '../api/client'
import type { AppLanguage, LocalizationState } from '../api/types'

export const useSettingsStore = defineStore('settings', () => {
  const language = ref<AppLanguage>('ja')
  const languages = ref<LocalizationState['languages']>([])
  const strings = ref<Record<string, string>>({})
  const isLoading = ref(false)
  const errorMessage = ref<string | null>(null)

  function replace(localization: LocalizationState) {
    language.value = localization.language
    languages.value = localization.languages
    strings.value = localization.strings
    document.documentElement.lang = localization.language
  }

  function text(key: string, ...args: Array<string | number>) {
    const format = strings.value[key] ?? key
    let index = 0
    return format.replace(/%@|%d/g, (token) => {
      const value = args[index++]
      if (value === undefined) return token
      return token === '%d' ? String(Number(value)) : String(value)
    })
  }

  async function load() {
    if (isLoading.value) return
    isLoading.value = true
    try {
      const panel = await overcueAPI.shortcutPanel()
      replace(panel.localization)
      errorMessage.value = null
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
    } finally {
      isLoading.value = false
    }
  }

  async function setLanguage(nextLanguage: AppLanguage) {
    if (nextLanguage === language.value) return
    isLoading.value = true
    try {
      const panel = await overcueAPI.shortcutCommand({
        action: 'setLanguage',
        language: nextLanguage,
      })
      replace(panel.localization)
      errorMessage.value = null
    } catch (error) {
      errorMessage.value = error instanceof Error ? error.message : String(error)
      throw error
    } finally {
      isLoading.value = false
    }
  }

  return {
    language,
    languages,
    strings,
    isLoading,
    errorMessage,
    replace,
    text,
    load,
    setLanguage,
  }
})
