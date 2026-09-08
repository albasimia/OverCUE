import { createRouter, createWebHistory } from 'vue-router'
import DashboardView from './views/DashboardView.vue'
import DevicesView from './views/DevicesView.vue'
import GroupPresetsView from './views/GroupPresetsView.vue'
import PresetsView from './views/PresetsView.vue'
import SettingsView from './views/SettingsView.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'dashboard', component: DashboardView },
    { path: '/presets', name: 'presets', component: PresetsView },
    { path: '/group-presets', name: 'group-presets', component: GroupPresetsView },
    { path: '/devices', name: 'devices', component: DevicesView },
    { path: '/settings', name: 'settings', component: SettingsView },
  ],
})
