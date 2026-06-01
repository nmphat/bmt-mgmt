# Route/access grep
grep -n "path: '/'\|path: '/sessions'\|path: '/members'\|path: '/member/:id'\|path: '/session/:id'\|path: '/login'\|path: '/create-session'\|requiresAuth\|requiresAdmin" src/router/index.ts

# Admin guard grep
grep -R "authStore.isAdmin" -n src/views src/components

# Supabase contract grep
grep -R "create_session_with_intervals\|from('members')\\.insert\|from('members')\\.update\|from('members')\\.delete\|view_member_debt_summary\|view_member_session_details\|view_session_summary\|calculate_session_costs\|finalize_session\|add_member_to_session_full_presence\|create_group_payment\|add_manual_payment\|session_costs_snapshot\|session_registrations\|interval_presence\|from('sessions').update" -n src

# Payment modal/fixed-layer grep
grep -R "role=\"dialog\"\|aria-modal=\"true\"\|max-h-\[88dvh\]\|env(safe-area-inset-bottom)\|min-h-11\|min-w-11\|payment-complete\|onUnmounted\|stopPolling" -n src/components src/views src/App.vue

# Locale parity node check
node -e "const fs=require('fs'); const s=fs.readFileSync('src/locales/messages.ts','utf8'); for (const k of ['loadError','sessionCardAria','createError','emptyState','activeStatus','inactiveStatus','permanentStatus','temporaryStatus','viewDetailsFor','editMember','deleteMember']) { const n=(s.match(new RegExp(k,'g'))||[]).length; if(n<2){throw new Error(k+' missing VI/EN parity')}} console.log('locale parity ok')"

# TypeScript type-check
pnpm type-check

# Production build
pnpm build
