# Project Retrospective: Badminton Session Manager

## Milestone: v1.0 — UI Refactor

**Shipped:** 2026-06-02  
**Phases:** 3  
**Plans:** 15  
**Tasks:** 37

### What Was Built

v1.0 turned the existing badminton management SPA into a mobile-first app while preserving the backend-owned Supabase business logic. It delivered a debt-first public home, mobile shell, member/session navigation, session-detail task cockpit, admin/supporting screen polish, QR/manual payment improvements, DB-backed bank settings, and regression evidence across source, build, i18n, browser smoke, UI review, security, and milestone audit.

### What Worked

- Preservation-first planning kept the risky Vue/Supabase contracts visible before UI changes.
- Requirement IDs across phase plans, summaries, verification, and audit made final coverage tractable.
- Browser harness screenshots and Open Design review caught issues that source checks could not, including NaN display, spacing, and mobile navigation refinements.
- Post-merge milestone audit found real backend-contract drift before final archive.

### What Was Inefficient

- Historical phase artifacts became stale after master/schema changes, requiring an audit-gap branch and follow-up PR/MR description.
- Manual visual UAT was skipped by instruction, so source/browser evidence had to substitute and some UX debt remains as low-priority follow-up.
- `gsd-sdk query` was unavailable in this runtime, requiring manual milestone archival and manual artifact audit.
- GitHub PR creation could not be automated because `gh`/token/browser auth were unavailable.

### Patterns Established

- Treat Open Design as a directional review artifact; never as a replacement for live backend contracts.
- Keep frontend fee/payment displays backend-owned through RPC/view/snapshot results.
- Protect admin mutations with route meta, UI gates, and handler checks.
- For schema drift discovered after merge, close with current source evidence and update top-level planning docs before milestone archive.
- Keep browser smoke production-safe unless explicit admin credentials and test data are provided.

### Key Lessons

- Milestone audit should run before merge when possible; otherwise follow-up branches must be expected.
- Historical verification artifacts need a "superseded by audit" note when backend contracts evolve after phase verification.
- Subjective UI feedback should be clarified before removing/restructuring components; the quick-nav ribbon spacing issue demonstrated this.
- Environment/tooling capabilities (`gsd-sdk query`, GitHub auth, browser certificate trust) should be checked early in closeout workflows.

### Cost Observations

- Model mix: not measured.
- Sessions: multiple GSD resume/quick/audit/secure/complete passes.
- Notable: parallel source/build/browser evidence reduced manual UAT needs, but late schema drift increased closeout overhead.

## Cross-Milestone Trends

| Trend | Observation | Action |
|-------|-------------|--------|
| Backend contracts | Supabase schema/RPC changes can invalidate verified UI work after merge. | Run milestone audit before merging and keep API docs/current schema references close to active source. |
| Browser evidence | Browser harness is valuable but depends on cert/profile/auth setup. | Record harness prerequisites and use dev-safe data for mutation smoke. |
| Planning artifacts | Long-lived phase docs can become historical rather than current. | Archive with explicit audit notes and keep current-state docs concise. |
