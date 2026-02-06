# Project: Badminton Session Manager - Frontend Requirements

## 1. Project Overview

Build a Single Page Application (SPA) to manage badminton sessions, track attendance by 30-minute intervals, and calculate shared costs fairly.

- **Primary Goal**: Replace manual spreadsheets with a mobile-friendly web app.
- **Backend**: Supabase (already set up with Tables, Views, RLS, and RPCs).

## 2. Tech Stack Constraints

- **Framework**: Vue 3 (using `<script setup>` and Composition API).
- **Language**: TypeScript (Strict mode).
- **Build Tool**: Vite.
- **Styling**: TailwindCSS (Mobile-first approach).
- **State Management**: Pinia (for User Auth state).
- **Data Fetching**: `@supabase/supabase-js`.
- **Router**: Vue Router.
- **Icons**: Lucide-vue-next or Heroicons.

## 3. Database Schema Context (Supabase)

The frontend acts as a UI layer for the existing Postgres backend.

- **Tables**: `sessions`, `members`, `session_intervals`, `session_registrations`, `interval_presence`.
- **Views**:
  - `view_session_summary` (id, title, status, session_date, total_intervals, total_registrations, court_fee_total, etc.)
- **RPC Functions** (Business Logic is here, DO NOT replicate in JS):
  - `calculate_session_costs(p_session_id)`: Returns cost breakdown per member.
  - `create_session_with_intervals(p_title, p_start_time, p_end_time, ...)`: Creates session & auto-generates intervals.

## 4. Key Features & Pages

### 4.1. Global App State

- Initialize Supabase Client.
- Handle Auth State (Login/Logout).
- If user is not logged in (`anon` role), they can still view "Active" or "Closed" sessions (Read-only).

### 4.2. Login View (`/login`)

- Simple form: Email & Password.
- Use `supabase.auth.signInWithPassword`.
- Redirect to Dashboard upon success.

### 4.3. Dashboard View (`/`)

- **Data Source**: Fetch from `view_session_summary`.
- **UI**: Grid or List of cards.
- **Card Details**: Title, Date (formatted), Status badge (Draft/Active/Closed).
- **Actions**:
  - "Create Session" button (Visible to Admin only).
  - Clicking a card navigates to `/session/:id`.

### 4.4. Create Session Modal/Page (Admin Only)

- **Inputs**: Title, Date, Start Time, End Time, Court Fee, Shuttle Fee.
- **Action**: Call RPC `create_session_with_intervals`.
- **Validation**: End Time must be after Start Time.

### 4.5. Session Detail View (`/session/:id`)

This is the main feature. Split into two main sections:

#### **A. The Attendance Matrix (Admin Interaction)**

- **Layout**: A Scrollable Table (Sticky first column for Member Names).
  - **Rows**: Members from `session_registrations`.
  - **Columns**: Intervals from `session_intervals` (Label: 18:00, 18:30...).
  - **Cells**: Checkboxes indicating presence.
- **Admin Actions**:
  - **Toggle Presence**: Clicking a cell upserts to `interval_presence`.
  - **Mark "Registered but Absent"**: A toggle/switch next to Member Name. If ON, disable their row but they still pay court fee (handled by backend).
  - **Bulk Toggle**: Click Member Name to toggle ALL intervals for that user.
- **Realtime**: Use Supabase Realtime to listen for changes in `interval_presence` to update UI instantly across devices.

#### **B. Cost Summary (Read-Only)**

- **Data Source**: RPC `calculate_session_costs(session_id)`.
- **Trigger**: Reload this data whenever the Attendance Matrix changes (or via Realtime payload).
- **Columns**:
  - Member Name.
  - Court Fee (Currency format).
  - Shuttle Fee (Currency format).
  - **Total (Final)**: Bold text. This is the rounded amount they must pay.
  - **Surplus**: Display the "Surplus Fund" (money gained from rounding) at the bottom.

## 5. TypeScript Interfaces

Use these types to ensure type safety:

```typescript
interface SessionSummary {
  id: string;
  title: string;
  status: 'draft' | 'active' | 'closed';
  session_date: string; // ISO string
  court_fee_total: number;
  shuttle_fee_total: number;
}

interface MemberCost {
  member_id: string;
  display_name: string;
  total_court_fee: number;
  total_shuttle_fee: number;
  final_total: number; // Rounded amount
  intervals_count: number;
}

interface Interval {
  id: string;
  start_time: string;
  idx: number;
}
```
