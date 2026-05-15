# Technology Stack

**Analysis Date:** 2025-01-13

## Languages

**Primary:**
- TypeScript ~5.9.3 - Strict mode, primary language for all business logic
- Vue/HTML (Vue 3 `.vue` Single File Components)

**Secondary:**
- CSS (TailwindCSS)
- JavaScript (build/config files only)

## Runtime

**Environment:**
- Node.js ^20.19.0 || >=22.12.0

**Package Manager:**
- pnpm (version managed by lockfile)
- Lockfile: `pnpm-lock.yaml` (present)

## Frameworks

**Core:**
- Vue 3 ^3.5.27 - Composition API with `<script setup>` syntax
  - Location: `src/` contains all Vue components
  - Pattern: Single File Components (.vue files)

**State Management:**
- Pinia ^3.0.4 - User Auth state and global state
  - Location: `src/stores/` (auth.ts, counter.ts, lang.ts)
  - Usage: `defineStore` pattern, Composition API

**Routing:**
- Vue Router ^5.0.1 - Navigation and page routing
  - Location: `src/router/index.ts`
  - Config: History mode with Vite BASE_URL

**Styling:**
- TailwindCSS ^4.1.18 - Utility-first CSS framework
  - Integration: `@tailwindcss/vite` plugin via `vite.config.ts`
  - Configuration: Inline (no tailwind.config.js found)
  - Approach: Mobile-first responsive design
- PostCSS ^8.5.6 - CSS transformation
- Autoprefixer ^10.4.24 - Browser compatibility

**UI & Icons:**
- lucide-vue-next ^0.563.0 - Vue 3 icon library
  - Usage: Icons throughout components (ChevronLeft, RefreshCcw, UserX, etc.)
- Heroicons - Listed in docs as alternative/supplement

**Notifications:**
- vue-toastification 2.0.0-rc.5 - Toast notifications for errors and feedback
  - Location: Used in `src/components/` and `src/views/`

**Date/Time:**
- date-fns ^4.1.0 - Date formatting and manipulation
  - Location: `src/views/SessionDetailView.vue` (vi, enUS locales)
  - Pattern: Locale-aware formatting with `vi` and `enUS`

## Build & Development Tools

**Build:**
- Vite ^7.3.1 - Frontend build tool and dev server
  - Config: `vite.config.ts`
  - Plugins: Vue, Vue JSX, Vue DevTools, TailwindCSS

**Dev Tools:**
- vite-plugin-vue-devtools ^8.0.5 - Vue debugging in dev
- @vitejs/plugin-vue ^6.0.3 - Vue SFC support
- @vitejs/plugin-vue-jsx ^5.1.3 - JSX support

**Type Checking:**
- vue-tsc ^3.2.4 - Vue TypeScript type checking
  - Config: `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json`
  - Script: `npm run type-check` runs `vue-tsc --build`

**TypeScript:**
- TypeScript ~5.9.3 - Language compiler
  - @tsconfig/node24 ^24.0.4 - Node 24 configuration preset
  - @types/node ^24.10.9 - Node type definitions
  - @vue/tsconfig ^0.8.1 - Vue TypeScript configuration

**Code Quality:**
- Prettier 3.8.1 - Code formatter
  - Config: `.prettierrc.json` (semi: false, singleQuote: true, printWidth: 100)
  - Script: `npm run format`

**Task Runner:**
- npm-run-all2 ^8.0.4 - Parallel/sequential task execution
  - Used in build script: `run-p type-check "build-only {@}" --`

## Key Dependencies

**Critical:**
- @supabase/supabase-js ^2.95.2 - Supabase client library
  - Provides: Database queries, Auth, Realtime subscriptions
  - Initialization: `src/lib/supabase.ts`
  - Usage: Throughout all data-fetching views and stores

## Configuration Files

**Environment:**
- `.env` - Runtime environment variables (not committed)
  - Required: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
- `.env.example` - Template showing required variables

**TypeScript:**
- `tsconfig.json` - Main config (references app and node configs)
- `tsconfig.app.json` - App-specific settings
  - Extends: `@vue/tsconfig/tsconfig.dom.json`
  - Paths: `@/*` → `./src/*`
  - Includes: `src/**/*.vue`, `src/**/*.ts`
  - Excludes: `src/**/__tests__/*`
- `tsconfig.node.json` - Build tool settings (via reference)

**Build & Dev:**
- `vite.config.ts` - Vite build configuration
  - Plugins: Vue, Vue JSX, Vue DevTools, TailwindCSS
  - Alias: `@` → `./src`

**Code Style:**
- `.prettierrc.json` - Prettier formatter config
  - Semi-colons: Off
  - Quotes: Single quotes
  - Line width: 100 characters

## Application Structure

**Entry Points:**
- `index.html` - HTML entry point (Vite SPA)
- `src/main.ts` - JavaScript entry point
  - Initializes: Vue app, Pinia store, Router
- `src/App.vue` - Root Vue component

**Development:**
- Script: `pnpm dev` - Vite dev server with HMR
- Script: `pnpm build` - Type-check + minified production build
- Script: `pnpm preview` - Preview production build
- Script: `pnpm type-check` - TypeScript validation only

## Platform Requirements

**Development:**
- Node.js 20.19.0 or 22.12.0+
- pnpm package manager
- VS Code with Volar extension (Vue language support)
- Chromium/Firefox with Vue DevTools

**Production:**
- Static hosting (SPA served on all routes)
- Supabase project with configured tables, views, and RPC functions
- CORS configured to allow frontend domain

---

*Stack analysis: 2025-01-13*
