---
quick_task: 260525-m9g
mode: quick
title: Browser harness testing
completed: 2026-05-25T09:05:00Z
baseline_head: 7b980bd94629f41f8b5ef1d1b2e6dbda461e24ef
app_url: http://localhost:5173/
application_code_changed: false
docs_commit_handled_by: gsd-quick-orchestrator
orchestrator_verified: true
---

# Quick Task 260525-m9g Summary: Browser harness testing

Smoke-tested the local badminton management app with the available `browser-harness` CLI against `http://localhost:5173/`.

## Verified Setup

- Baseline `HEAD` matched the requested commit: `7b980bd94629f41f8b5ef1d1b2e6dbda461e24ef`.
- `curl -I http://localhost:5173/` returned `HTTP/1.1 200 OK`.
- `browser-harness doctor` reported:
  - Chrome running: OK
  - Daemon alive: OK
  - Active browser connections: OK, 1 connection
  - Optional profile/cloud checks failed only for profile sync/API-key features.

## Browser Surfaces Tested

| Surface | Result |
| --- | --- |
| `/` | Loaded page title `🐴 Badminton Management`; visible heading `Member Debts`; navigation links rendered. |
| Language toggle | Toggled UI labels from English to Vietnamese (`Công Nợ`, `Tìm tên thành viên...`). |
| Debt search input | Search input was visible and accepted typed input; data results were blocked by backend network failure noted below. |
| `/members` | Route loaded; visible heading `Member Management`. |
| `/sessions` | Route loaded; visible heading `Badminton Sessions`. |
| `/login` | Route loaded; email/password fields and submit button rendered. |
| `/create-session` unauthenticated | Redirected to `/login` as expected. |

## Findings

1. Primary shell/navigation rendered successfully in Chrome through browser harness.
2. Local app documents and Vite assets returned HTTP 200/304, with no captured runtime exceptions in the tested route pass.
3. Data-backed Supabase requests failed in the browser with `net::ERR_CERT_AUTHORITY_INVALID` on preflight/fetch requests.
   - Impact: debt data showed an error state (`Không tải được dữ liệu...`), and member/session data could not be verified beyond route/header rendering.
   - No application-code change was made because this appears to be an environment/certificate trust issue in the current browser harness/runtime, not a verified app regression.
4. Follow-up bypass test succeeded by launching a dedicated dev-only Chrome/CDP instance with `--ignore-certificate-errors`.
   - Browser harness was reconnected to `http://127.0.0.1:9243` after `browser-harness --reload`.
   - Supabase preflight/fetch requests for `view_member_debt_summary` returned HTTP 200.
   - The debt table loaded real rows including `Minh Quân`, `Ba Phát`, `khang phạm`, and VND totals.
5. Full-page screenshots were captured through the CloakBrowser bypass instance for mobile and desktop route coverage.
   - Captured routes: debt home, members, sessions, first debtor detail, first session detail, login, and unauthenticated create-session auth gate.
   - `/create-session` correctly redirected to `/login` while unauthenticated.

## Dev-only Certificate Bypass

Use this only for local QA on a trusted network/profile. It disables certificate validation for that browser instance.

```bash
CHROME=/home/phatngo/.cloakbrowser/chromium-146.0.7680.177.5/chrome
PORT=9243
PROFILE=/tmp/badminton-mgmt-browser-ignore-certs-9243

rm -rf "$PROFILE"
mkdir -p "$PROFILE"
"$CHROME" \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --disable-extensions \
  --disable-sync \
  --no-first-run \
  --no-default-browser-check \
  --ignore-certificate-errors \
  --allow-insecure-localhost \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$PROFILE" \
  about:blank
```

Then reload browser-harness and run against `cdp_url: http://127.0.0.1:9243`.

Current bypass browser process during this test: PID `90889`.

## Screenshots

Saved under `.planning/quick/260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing/screenshots/`:

| Viewport | Screens |
| --- | --- |
| Mobile | `mobile-home-debt.png`, `mobile-members.png`, `mobile-sessions.png`, `mobile-member-detail-first-debtor.png`, `mobile-session-detail-first-session.png`, `mobile-login.png`, `mobile-create-session-auth-gate.png` |
| Desktop | `desktop-home-debt.png`, `desktop-members.png`, `desktop-sessions.png`, `desktop-member-detail-first-debtor.png`, `desktop-session-detail-first-session.png`, `desktop-login.png`, `desktop-create-session-auth-gate.png` |

## Recommendations

- Fix or trust the certificate chain for the Supabase endpoint in the browser harness environment, then rerun the smoke test to verify real debt/member/session data flows.
- Prefer installing the company root CA into the Chrome/OS trust store for longer-lived work; use the bypass flag only for short local smoke tests.
- Keep the current no-code-change result as a harness/environment QA record.

## Files Changed

- `.planning/quick/260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing/260525-m9g-PLAN.md`
- `.planning/quick/260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing/260525-m9g-SUMMARY.md`
- `.planning/quick/260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing/screenshots/*.png`
- `.planning/STATE.md`
