<script setup lang="ts">
import type { AppLanguage } from '../api/types'
import { useSettingsStore } from '../stores/settings'

const settings = useSettingsStore()

function changeLanguage(event: Event) {
  const language = (event.target as HTMLSelectElement).value as AppLanguage
  void settings.setLanguage(language).catch(() => undefined)
}
</script>

<template>
  <section class="standard-page">
    <div class="native-page-heading">
      <div class="native-page-title">
        <h1>{{ settings.text('settings.title') }}</h1>
      </div>
    </div>

    <div class="native-detail-card settings-card">
      <div class="detail-row">
        <span>{{ settings.text('settings.language') }}</span>
        <select
          class="native-select"
          :value="settings.language"
          :disabled="settings.isLoading"
          @change="changeLanguage"
        >
          <option v-for="language in settings.languages" :key="language.id" :value="language.id">
            {{ language.name }}
          </option>
        </select>
      </div>
      <div class="setting-note">
        {{ settings.text('settings.language.help') }}
      </div>
      <p v-if="settings.errorMessage" class="page-status error" role="alert">
        {{ settings.errorMessage }}
      </p>
    </div>
  </section>
</template>
