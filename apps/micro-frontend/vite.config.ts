import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import * as vitePluginFederation from '@originjs/vite-plugin-federation'

// The package's CJS/ESM dual-build confuses TS's default-export inference
// under nodenext; the runtime export is a plain callable function.
const federation = (vitePluginFederation as { default: unknown }).default as (options: {
  name: string
  filename?: string
  exposes?: Record<string, string>
  remotes?: Record<string, string>
  shared?: string[]
}) => Plugin

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    federation({
      name: 'micro_frontend',
      filename: 'remoteEntry.js',
      exposes: {
        './Widget': './src/Widget.tsx',
      },
      shared: ['react', 'react-dom'],
    }),
  ],
  server: {
    port: 4174,
    cors: true,
  },
  preview: {
    port: 4174,
    cors: true,
  },
  build: {
    modulePreload: false,
    target: 'esnext',
    minify: false,
    cssCodeSplit: false,
  },
})
