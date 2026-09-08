import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  base: './',
  server: {
    host: '127.0.0.1',
    port: 4174,
    strictPort: true,
    proxy: {
      '/api': {
        target: process.env.OVERCUE_API_ORIGIN ?? 'http://127.0.0.1:4173',
        changeOrigin: false,
      },
    },
  },
})
