import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import basicSsl from '@vitejs/plugin-basic-ssl';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

/** Emits sw.js with this build's complete file list baked in, so the first install caches the whole app. */
function swPrecache(): Plugin {
  const template = path.join(import.meta.dirname, 'sw.js');
  const publicDir = path.join(import.meta.dirname, 'public');
  return {
    name: 'sw-precache',
    apply: 'build',
    generateBundle(_options, bundle) {
      const files = [...Object.keys(bundle), ...fs.readdirSync(publicDir)].filter((f) => !f.endsWith('.map')).sort();
      const id = crypto.createHash('sha1').update(files.join('\n')).digest('hex').slice(0, 10);
      const source = fs.readFileSync(template, 'utf8')
        .replace('__BUILD_ID__', id)
        .replace('__PRECACHE__', JSON.stringify(files.map((f) => `./${f}`)));
      this.emitFile({ type: 'asset', fileName: 'sw.js', source });
    },
  };
}

// Relative base so the built app works from any static host or subfolder (GitHub Pages, Cloudflare Pages…).
// The dev server is HTTPS on the LAN so a phone camera works while developing.
export default defineConfig(({ command, isPreview }) => ({
  root: import.meta.dirname,
  base: './',
  plugins: [react(), command === 'serve' && !isPreview && basicSsl(), swPrecache()],
  build: { outDir: '../dist', emptyOutDir: true },
  server: { host: true },
  preview: { host: true },
}));
