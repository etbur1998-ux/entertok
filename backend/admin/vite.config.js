import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3001,
    // SPA fallback — all unknown routes → index.html
    historyApiFallback: true,
    proxy: {
      '/api':     { target: 'http://192.168.1.7:8082', changeOrigin: true },
      '/uploads': { target: 'http://192.168.1.7:8082', changeOrigin: true },
      '/health':  { target: 'http://192.168.1.7:8082', changeOrigin: true },
      '/debug':   { target: 'http://192.168.1.7:8082', changeOrigin: true },
      '/ws':      { target: 'http://192.168.1.7:8082', changeOrigin: true, ws: true },
      '/meeting': { target: 'http://192.168.1.7:8082', changeOrigin: true },
    }
  },
  build: {
    // Silence the chunk size warning
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor:   ['react', 'react-dom', 'react-router-dom'],
          charts:   ['recharts'],
          icons:    ['lucide-react'],
          http:     ['axios'],
        }
      }
    }
  }
})
