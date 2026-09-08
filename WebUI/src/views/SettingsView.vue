<script setup lang="ts">
import { useSettingsStore } from '../stores/settings'

const settings = useSettingsStore()
</script>

<template>
  <section class="standard-page">
    <div class="native-page-heading">
      <div class="native-page-title">
        <h1>Settings</h1>
        <p>Application preferences.</p>
      </div>
    </div>

    <div class="native-detail-card settings-card">
      <div class="detail-row">
        <span>Language</span>
        <select v-model="settings.language">
          <option value="ja">日本語</option>
          <option value="en">English</option>
          <option value="zh-Hans">简体中文</option>
        </select>
      </div>
      <div class="setting-note">
        Web UI state is intentionally separate from runtime ownership. Persistence will be wired through the local OverCUE API.
      </div>
    </div>
  </section>
</template>
