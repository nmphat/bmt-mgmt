# GEMINI.md - Project Context: Badminton Session Manager

This file provides instructional context for Gemini CLI when working on the `badminton-mgmt` project.

## Project Overview

The **Badminton Session Manager** is a Single Page Application (SPA) designed to manage badminton sessions, track attendance by 30-minute intervals, and calculate shared costs fairly. It acts as a UI layer for an existing Supabase/Postgres backend.

- **Primary Goal**: Replace manual spreadsheets with a mobile-friendly web app.
- **Backend**: Supabase (Tables, Views, RLS, and RPCs are already set up).
- **Core Logic**: Business logic resides in Postgres RPC functions; the frontend must not replicate this logic.

## Tech Stack

- **Framework**: Vue 3 (Composition API with `<script setup>`)
- **Language**: TypeScript (Strict mode)
- **Build Tool**: Vite
- **State Management**: Pinia (primarily for User Auth state)
- **Routing**: Vue Router
- **Styling**: TailwindCSS (Mobile-first approach)
- **Data Fetching**: `@supabase/supabase-js`
- **Icons**: Lucide-vue-next or Heroicons

## Database & API Context (Supabase)

Detailed technical API specifications can be found in `docs/api.yaml`.

### Tables & Views

- **Tables**: `sessions`, `members`, `session_intervals`, `session_registrations`, `interval_presence`.
- **Views**: `view_session_summary` (contains aggregated session data like totals and status).

### Key RPC Functions

- `calculate_session_costs(p_session_id)`: Returns cost breakdown per member.
- `create_session_with_intervals(p_title, p_start_time, p_end_time, p_court_fee, p_shuttle_fee, p_created_by)`: Creates session and auto-generates intervals.

## Key Features

- **Attendance Matrix**: Sticky-column table for tracking member presence in 30-min intervals.
- **Cost Summary**: Read-only breakdown of court fees, shuttle fees, and rounded totals.
- **Real-time Sync**: Uses Supabase Realtime to reflect attendance changes instantly.
- **Admin Actions**: Creating sessions, toggling attendance, and marking "Registered but Absent".

## Development Conventions

- **Logic Placement**: **NO Business Logic in JS**. Always use the data returned by Supabase RPCs.
- **Formatting**:
  - **Dates**: Use `DD/MM/YYYY` for dates and `HH:mm` for times.
  - **Currency**: Format as Vietnamese Dong (e.g., `54.000 ₫`).
- **Error Handling**: Use toast notifications for API errors (e.g., `vue-toastification`).
- **Mobile First**: Ensure the Attendance Matrix is horizontally scrollable and responsive.
- **Naming**: PascalCase for components, camelCase for variables/functions.

## Building and Running

- **Install**: `pnpm install`
- **Dev**: `pnpm dev`
- **Build**: `pnpm build`
- **Type Check**: `pnpm type-check`
- **Format**: `pnpm format`

## Project Structure

- `src/App.vue`: Root component.
- `src/main.ts`: Entry point.
- `src/router/`: App routes.
- `src/stores/`: Pinia stores (Auth, etc.).
- `docs/summary.md`: Primary requirements and reference document.
- `docs/api.yaml`: Technical API specification (Swagger/OpenAPI).
