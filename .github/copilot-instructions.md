# Copilot Instructions

## Goal
Support this badminton management system quickly with accurate context and safe changes.

## Project Context
- Workspace repo: bmt-mgmt
- Default Supabase project: `bufpmpehugzysvmbjlub`
- Source of truth priority: live DB (via Supabase MCP) > docs > guessed assumptions
- Payment webhook provider: SePay is standard; Casso is legacy only

## Required Onboarding For New Tasks
Before implementing any non-trivial task, quickly read:
- `docs/context/00-project-overview.md`
- `docs/context/01-database-schema.md`
- `docs/context/02-business-logic.md`
- `docs/context/05-payment-domain.md`
- `docs/context/06-frontend-arch.md`
- `docs/context/08-bugs-and-roadmap.md`

Then provide:
1. A short understanding summary
2. Any docs/code/DB mismatches
3. Implementation steps

## Database Safety Rules
- Always ask for confirmation before any DB write action:
  - migrations
  - DDL/DML
  - function replacements
  - data updates/deletes
- Read-only checks are allowed by default.
- If DB and docs conflict, report clearly and propose fix direction.

## Documentation Sync Rules
- If a task changes schema, RPC behavior, or feature flow, update relevant docs in the same task (after user approval).
- Keep `docs/context` and `docs/sql-export` aligned with current system behavior.

## Frontend & i18n Rules
- Keep Vietnamese wording consistent and natural; avoid mixed EN/VI terms in user-facing labels.
- Remove unused i18n keys when confirmed.
- Define missing i18n keys explicitly; do not leave fallback text in production UI.

## Delivery Style
- Be concise and action-oriented.
- For each task, include:
  - what changed
  - where changed
  - validation performed
  - any follow-up risks or suggestions
