# Task 5: Final Verification

**Objective:** Verify all changes compile, build, and have no stale references.

**Files:**
- Verify: all 4 modified/created files

**Plan:** `docs/superpowers/plans/2026-06-21-cash-payment-home.md` Task 5

---

## Steps

### Step 1: TypeScript check

```bash
cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit
```

Expected: No errors.

### Step 2: Build check

```bash
cd /home/phat/bmt-mgmt && pnpm run build
```

Expected: Build succeeds.

### Step 3: Check for stale references

```bash
cd /home/phat/bmt-mgmt && grep -rn "cashPayHome" src/
```

Expected: No results (key was removed from spec).

### Step 4: Verify i18n keys exist

```bash
cd /home/phat/bmt-mgmt && grep -n "cashAllocationTitle\|cashPaymentSuccess\|cashPaymentPartial\|cashAllocationSummary" src/locales/messages.ts
```

Expected: 8 matches (4 vi + 4 en).

### Step 5: Verify isAdmin prop threaded correctly

```bash
cd /home/phat/bmt-mgmt && grep -n "isAdmin" src/components/HomeDebtTable.vue
```

Expected: matches in defineProps and v-if directives.

### Step 6: Final commit if needed

```bash
git add -A
git commit -m "feat(payment): complete cash payment on home page"
```
