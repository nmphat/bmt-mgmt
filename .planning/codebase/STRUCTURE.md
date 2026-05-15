# Codebase Structure

**Analysis Date:** 2025-01-17

## Directory Layout

```
badminton-mgmt/
├── src/                           # Application source code
│   ├── main.ts                    # Vue app initialization entry point
│   ├── App.vue                    # Root component (header, router outlet)
│   ├── assets/
│   │   └── main.css               # Global styles (imports TailwindCSS)
│   ├── components/                # Reusable UI components
│   │   ├── AppHeader.vue          # Navigation header (displayed globally)
│   │   ├── HomeDebtTable.vue      # Paginated debt table for home page
│   │   ├── PaymentQRModal.vue     # Modal for displaying payment QR code
│   │   └── ManualPaymentModal.vue # Modal for manual payment entry
│   ├── composables/               # Reusable composition functions (empty)
│   ├── lib/
│   │   └── supabase.ts            # Supabase client initialization
│   ├── locales/
│   │   └── messages.ts            # i18n message keys and translations
│   ├── router/
│   │   └── index.ts               # Vue Router setup and auth guards
│   ├── stores/
│   │   ├── auth.ts                # Pinia auth store (user session, profile)
│   │   ├── lang.ts                # Pinia language store
│   │   └── counter.ts             # Pinia example/demo store
│   ├── types/
│   │   └── index.ts               # TypeScript interfaces for all data models
│   ├── utils/
│   │   ├── formatters.ts          # Formatting utilities (name shortening, etc.)
│   │   └── time.ts                # Time/date helper functions
│   └── views/                     # Page-level components (routes)
│       ├── HomePage.vue           # Home/dashboard with debt summary (/)
│       ├── LoginView.vue          # Login form (/login)
│       ├── DashboardView.vue      # Admin session list (/sessions)
│       ├── CreateSessionView.vue  # Admin create session (/create-session)
│       ├── SessionDetailView.vue  # Attendance matrix & costs (/session/:id)
│       ├── MemberView.vue         # Member list (/members)
│       └── MemberDetailView.vue   # Member profile detail (/member/:id)
├── docs/                          # Project documentation
│   ├── api.yaml                   # OpenAPI/Swagger specification
│   └── summary.md                 # Frontend requirements & API reference
├── public/                        # Static assets (favicon, etc.)
├── .planning/                     # GSD planning artifacts
│   └── codebase/                  # Codebase mapping documents
├── .vscode/                       # VS Code workspace settings
├── index.html                     # HTML entry point (mounts Vue app to #app)
├── tsconfig.json                  # Root TypeScript config (references app/node)
├── tsconfig.app.json              # Application TypeScript config
├── tsconfig.node.json             # Node/build TypeScript config
├── vite.config.ts                 # Vite build configuration
├── .prettierrc.json               # Prettier code formatter config
├── package.json                   # Dependencies and scripts
├── pnpm-lock.yaml                 # Locked dependency versions (pnpm)
├── GEMINI.md                      # Project context for AI assistant
├── README.md                      # Basic setup instructions
└── .gitignore                     # Git ignore rules
```

## Directory Purposes

**src/:**
- Purpose: All application source code
- Contains: TypeScript/Vue components, utilities, stores, types
- Key files: `main.ts`, `App.vue`

**src/components/:**
- Purpose: Reusable UI components (not full pages)
- Contains: Modal dialogs, table components, headers
- Key files: `AppHeader.vue` (used globally), `PaymentQRModal.vue`, `ManualPaymentModal.vue`

**src/composables/:**
- Purpose: Reusable composition functions (Composition API extracts)
- Contains: Custom hooks/composables
- Key files: Currently empty; intended for complex shared logic

**src/lib/:**
- Purpose: External library initialization and configuration
- Contains: Supabase client singleton
- Key files: `supabase.ts`

**src/locales/:**
- Purpose: Internationalization (i18n) text and translations
- Contains: Message keys and Vietnamese/English translations
- Key files: `messages.ts`

**src/router/:**
- Purpose: Vue Router setup and route definitions
- Contains: Route configuration, auth guards
- Key files: `index.ts`

**src/stores/:**
- Purpose: Pinia stores for global state management
- Contains: Auth store (user + profile), language store
- Key files: `auth.ts` (primary), `lang.ts`, `counter.ts` (demo)

**src/types/:**
- Purpose: TypeScript interfaces and type definitions
- Contains: Interfaces for Supabase tables, views, RPCs
- Key files: `index.ts`

**src/utils/:**
- Purpose: Utility functions and helpers
- Contains: Formatters (name, currency, date), time utilities
- Key files: `formatters.ts`, `time.ts`

**src/views/:**
- Purpose: Page-level components (one per route)
- Contains: Full-page components mapped to routes
- Key files: `HomePage.vue` (debt summary), `SessionDetailView.vue` (attendance matrix), `LoginView.vue`

**docs/:**
- Purpose: Project documentation
- Contains: API specification, requirements summary
- Key files: `api.yaml` (OpenAPI spec), `summary.md` (frontend requirements)

**public/:**
- Purpose: Static assets served as-is
- Contains: Favicon, images, etc.

## Key File Locations

**Entry Points:**
- `index.html`: HTML root; imports `src/main.ts`
- `src/main.ts`: Vue app creation and mounting
- `src/App.vue`: Root Vue component; renders AppHeader and router-view
- `src/router/index.ts`: Route definitions and auth guards

**Configuration:**
- `vite.config.ts`: Vite build config (Vue, JSX, TailwindCSS, DevTools plugins)
- `tsconfig.json`: Root TypeScript configuration
- `tsconfig.app.json`: App-level TypeScript settings (strict mode)
- `.prettierrc.json`: Code formatter settings
- `package.json`: Dependencies (Vue 3, Pinia, Supabase, TailwindCSS, date-fns)

**Core Logic:**
- `src/lib/supabase.ts`: Supabase client initialization
- `src/stores/auth.ts`: Authentication state and user profile management
- `src/types/index.ts`: All TypeScript interfaces matching Supabase schema

**Key Views:**
- `src/views/HomePage.vue`: Member debt summary (main landing page)
- `src/views/SessionDetailView.vue`: Attendance matrix and cost breakdown
- `src/views/LoginView.vue`: Email/password login
- `src/views/CreateSessionView.vue`: Admin form to create sessions

**Utilities:**
- `src/utils/formatters.ts`: Name shortening, number formatting
- `src/utils/time.ts`: Date/time helpers

**Components:**
- `src/components/AppHeader.vue`: Global navigation header
- `src/components/HomeDebtTable.vue`: Paginated member debt table
- `src/components/PaymentQRModal.vue`: QR code payment modal
- `src/components/ManualPaymentModal.vue`: Manual payment entry modal

**Documentation:**
- `docs/summary.md`: Frontend requirements and API reference
- `docs/api.yaml`: OpenAPI/Swagger specification
- `GEMINI.md`: Project context and conventions for AI assistants
- `README.md`: Setup instructions

## Naming Conventions

**Files:**
- Vue components: PascalCase (e.g., `AppHeader.vue`, `SessionDetailView.vue`)
- TypeScript/JS utilities: camelCase (e.g., `formatters.ts`, `supabase.ts`)
- Views: PascalCase with `View` suffix (e.g., `LoginView.vue`, `SessionDetailView.vue`)
- Stores: camelCase (e.g., `auth.ts`, `lang.ts`)

**Directories:**
- Lowercase plural nouns (e.g., `components`, `stores`, `views`, `utils`, `types`)

**TypeScript Interfaces/Types:**
- PascalCase (e.g., `SessionSummary`, `MemberCost`, `CostSnapshot`)
- Suffixes: `Summary` for aggregated views, `Detail` for detailed objects, `Snapshot` for immutable copies

**Functions & Variables:**
- camelCase (e.g., `fetchProfile()`, `isAuthenticated`, `currentPage`)
- Boolean variables/computed: prefix with `is` or `has` (e.g., `isAdmin`, `hasMore`)
- Ref/reactive variables in Vue: suffix with descriptive noun (e.g., `loading`, `members`, `selectedGroupPayment`)

**Route Names & Paths:**
- Kebab-case for paths (e.g., `/login`, `/session/:id`, `/create-session`)
- camelCase for route names (e.g., `'login'`, `'sessionDetail'`, `'createSession'`)

## Where to Add New Code

**New Feature (e.g., expense tracking):**
- Primary code: `src/views/ExpenseView.vue` (if page-level) or `src/components/ExpenseForm.vue` (if reusable)
- Types: Add interface to `src/types/index.ts`
- Route: Add to `src/router/index.ts`
- Utils: Add helpers to `src/utils/` if needed
- Store: Add Pinia store in `src/stores/` if requires global state

**New Component/UI Module:**
- Implementation: `src/components/MyComponent.vue` (reusable) or directly in view if one-off
- Pattern: Use `<script setup lang="ts">`, Composition API, TailwindCSS classes
- Icons: Import from `lucide-vue-next`

**Utilities & Helpers:**
- Formatting/parsing: `src/utils/formatters.ts`
- Date/time operations: `src/utils/time.ts`
- General helpers: Consider creating new file in `src/utils/` if large

**Type Definitions:**
- All Supabase models: `src/types/index.ts`
- Component-specific types: Define in component file with TypeScript generics

**Stores (Global State):**
- Authentication: `src/stores/auth.ts`
- Language/i18n: `src/stores/lang.ts`
- New domain (e.g., notifications): Create `src/stores/notifications.ts`

**Composables:**
- Complex reusable logic: `src/composables/useMyLogic.ts`
- Custom hooks: Follow Vue Composition API conventions

## Special Directories

**dist/:**
- Purpose: Build output (production-ready compiled assets)
- Generated: Yes (by `pnpm build`)
- Committed: No (in .gitignore)

**node_modules/:**
- Purpose: Installed npm/pnpm dependencies
- Generated: Yes (by `pnpm install`)
- Committed: No (in .gitignore)

**.planning/:**
- Purpose: GSD workflow planning artifacts
- Generated: Yes (by GSD commands)
- Committed: No (intended for local planning)

**.env & .env.example:**
- Purpose: Environment variables for Supabase connection
- Generated: Manual (copy .env.example to .env and fill in values)
- Committed: .env.example only; .env is private (in .gitignore)
- Required vars: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`

---

*Structure analysis: 2025-01-17*
