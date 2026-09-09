import { createRouter, createWebHistory } from 'vue-router'
import DevicesView from './views/DevicesView.vue'
import GroupPresetsView from './views/GroupPresetsView.vue'
import SettingsView from './views/SettingsView.vue'
import ShortcutsView from './views/ShortcutsView.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/shortcuts' },
    { path: '/shortcuts', name: 'shortcuts', component: ShortcutsView },
    { path: '/presets', redirect: '/shortcuts' },
    { path: '/devices', name: 'devices', component: DevicesView },
    { path: '/group-presets', name: 'group-presets', component: GroupPresetsView },
    { path: '/settings', name: 'settings', component: SettingsView },
    { path: '/:pathMatch(.*)*', redirect: '/shortcuts' },
  ],
})
