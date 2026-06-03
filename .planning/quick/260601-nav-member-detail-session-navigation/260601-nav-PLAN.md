---
quick_id: 260601-nav
status: complete
description: Member detail session history navigates to session detail when clicking a session
completed_at: "2026-06-01T14:34:00+07:00"
---

# Quick Task 260601-nav: Member detail session navigation

## Goal

On `/member/:id`, clicking a session in the member participation/debt history should navigate to `/session/:session_id`.

## Tasks

1. Update `src/views/MemberDetailView.vue` so mobile session cards and desktop session rows behave as accessible link targets to the session detail page.
2. Preserve existing QR payment behavior by stopping row/card click propagation from QR buttons.
3. Verify with type-check/build and a browser smoke check that clicking a session navigates while QR opens the payment modal.
