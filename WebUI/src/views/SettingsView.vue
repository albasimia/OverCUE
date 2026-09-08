<script setup lang="ts">
import { useSettingsStore } from '../stores/settings'

const settings = useSettingsStore()
</script>

<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Application</p>
        <h1>Settings</h1>
      </div>
    </div>

    <div class="card settings-card">
      <label>
        <span>Language</span>
        <select v-model="settings.language">
          <option value="ja">日本語</option>
          <option value="en">English</option>
          <option value="zh-Hans">简体中文</option>
        </select>
      </label>
      <div class="setting-note">
        Web UI state is intentionally separate from runtime ownership. Persistence will be wired through the local OverCUE API.
      </div>
    </div>
  </section>
</template>
