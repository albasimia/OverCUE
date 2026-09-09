import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { router } from './router'
import './styles.css'
import './shortcuts.css'
import './shortcuts-preset.css'
import './shortcuts-responsive.css'
import './shortcuts-dialog.css'
import './ack05-device.css'
import './group-presets.css'

createApp(App)
  .use(createPinia())
  .use(router)
  .mount('#app')
