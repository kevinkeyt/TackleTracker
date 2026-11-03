import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import basicSsl from '@vitejs/plugin-basic-ssl';

// Dev server is HTTPS on the LAN so phone cameras work; API calls go to the Node server.
export default defineConfig({
  root: import.meta.dirname,
  plugins: [react(), basicSsl()],
  build: { outDir: '../dist', emptyOutDir: true },
  server: {
    host: true,
    proxy: {
      '/api': 'http://localhost:3000',
      '/images': 'http://localhost:3000',
    },
  },
});
