import { createRouter, createWebHistory } from 'vue-router'
import DevicesView from './views/DevicesView.vue'
import GroupPresetsView from './views/GroupPresetsView.vue'
import PresetsView from './views/PresetsView.vue'
import SettingsView from './views/SettingsView.vue'
import ShortcutsView from './views/ShortcutsView.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/shortcuts' },
    { path: '/shortcuts', name: 'shortcuts', component: ShortcutsView },
    { path: '/presets', name: 'presets', component: PresetsView },
    { path: '/devices', name: 'devices', component: DevicesView },
    { path: '/group-presets', name: 'group-presets', component: GroupPresetsView },
    { path: '/settings', name: 'settings', component: SettingsView },
  ],
})
