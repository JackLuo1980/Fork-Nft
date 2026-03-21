# Login/Auth and Shell Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully usable Chinese login entry, persistent session handling, and route gating so every management page is protected before we add server/node install, update, uninstall, and auto-upgrade flows.

**Architecture:** Keep the current backend login API and token model as the source of truth, and tighten the frontend around it. The frontend owns the login screen, session storage, and route redirects; the backend owns auth contract stability and 401 behavior. Verification should happen in three layers: backend contract tests, frontend build checks, and a Docker-based test-environment smoke test.

**Tech Stack:** Go `net/http` + GORM, React 18, TypeScript, React Router, axios, Docker Compose, browser smoke verification.

---

### Task 1: Lock the auth contract and 401 behavior

**Files:**
- Modify: `go-backend/internal/http/handler/handler.go`
- Modify: `go-backend/internal/http/middleware/auth.go`
- Test: `go-backend/tests/contract/auth_contract_test.go`
- Test: `go-backend/tests/contract/migration_contract_test.go`

- [ ] **Step 1: Write the failing contract assertions**

Add or tighten contract coverage for:
- login returns the expected token / role / name payload
- invalid or missing login credentials return a stable failure response
- captcha-gated login remains compatible with the existing contract tests
- unauthorized requests keep returning the same 401 envelope the frontend already understands

- [ ] **Step 2: Run the contract tests and confirm the current gaps**

Run:

```bash
cd go-backend && go test ./tests/contract/... -run 'Auth|Migration' -v
```

Expected: at least one assertion fails or highlights the current contract gap that needs to be aligned.

- [ ] **Step 3: Make the smallest backend changes needed**

Keep the handler signatures stable. Adjust only the login/authorization flow that the frontend depends on, and avoid touching unrelated CRUD handlers.

- [ ] **Step 4: Re-run the contract tests**

Run:

```bash
cd go-backend && go test ./tests/contract/... -run 'Auth|Migration' -v
```

Expected: tests pass and the login/401 contract stays stable.

- [ ] **Step 5: Commit the backend auth work**

```bash
git add go-backend/internal/http/handler/handler.go go-backend/internal/http/middleware/auth.go go-backend/tests/contract/auth_contract_test.go go-backend/tests/contract/migration_contract_test.go
git commit -m "feat: stabilize login auth contract"
```

### Task 2: Polish the Chinese login entry

**Files:**
- Modify: `vite-frontend/src/pages/index.tsx`
- Modify: `vite-frontend/src/components/brand-logo.tsx`
- Modify: `vite-frontend/src/components/icons.tsx`
- Modify: `vite-frontend/src/api/index.ts`

- [ ] **Step 1: Write the failing UI expectations**

Capture the expected login behavior in the page itself:
- Chinese copy by default
- clear username/password validation text
- login success routes to the dashboard
- default logo falls back cleanly when no custom `app_logo` exists

- [ ] **Step 2: Rebuild the frontend and check the current page**

Run:

```bash
cd vite-frontend && npm run build
```

Expected: build succeeds, and the login page still compiles against the existing auth/session helpers.

- [ ] **Step 3: Implement the minimal login-page changes**

Keep the page readable and small:
- keep the login form as the entry route
- keep the captcha branch intact
- keep the post-login redirect behavior stable
- keep the current default logo fallback behavior

- [ ] **Step 4: Re-run the frontend build**

Run:

```bash
cd vite-frontend && npm run build
```

Expected: build passes without type errors.

- [ ] **Step 5: Commit the login-page polish**

```bash
git add vite-frontend/src/pages/index.tsx vite-frontend/src/components/brand-logo.tsx vite-frontend/src/components/icons.tsx vite-frontend/src/api/index.ts
git commit -m "feat: polish chinese login entry"
```

### Task 3: Harden session storage and protected routing

**Files:**
- Modify: `vite-frontend/src/App.tsx`
- Modify: `vite-frontend/src/utils/auth.ts`
- Modify: `vite-frontend/src/utils/session.ts`
- Modify: `vite-frontend/src/utils/logout.ts`
- Modify: `vite-frontend/src/api/network.ts`
- Modify: `vite-frontend/src/pages/profile.tsx`
- Modify: `vite-frontend/src/pages/change-password.tsx`

- [ ] **Step 1: Write the failing route/session expectations**

Make the intended flow explicit:
- unauthenticated users stay on `/`
- authenticated users are redirected away from `/`
- expired tokens clear session state and return to `/`
- logout always clears session state but preserves UI preferences

- [ ] **Step 2: Exercise the current redirect behavior**

Run:

```bash
cd vite-frontend && npm run build
```

Expected: build still works before the gating changes are tightened.

- [ ] **Step 3: Implement the route/session hardening**

Keep the changes localized to the shared auth/session helpers and the router shell. Avoid baking auth logic into individual pages.

- [ ] **Step 4: Re-run the frontend build**

Run:

```bash
cd vite-frontend && npm run build
```

Expected: build passes and the protected route shell still composes cleanly.

- [ ] **Step 5: Commit the routing/session work**

```bash
git add vite-frontend/src/App.tsx vite-frontend/src/utils/auth.ts vite-frontend/src/utils/session.ts vite-frontend/src/utils/logout.ts vite-frontend/src/api/network.ts vite-frontend/src/pages/profile.tsx vite-frontend/src/pages/change-password.tsx
git commit -m "feat: harden session gating"
```

### Task 4: Docker test-environment smoke verification

**Files:**
- Modify: `README.md`
- Modify: `plans/055-login-auth-and-shell-gating.md`
- Verify: `docker-compose.yml`
- Verify: `docker-compose.test.yml`

- [ ] **Step 1: Rebuild the test environment with Docker Compose**

Run:

```bash
cd /opt/realmflow && docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --build
```

Expected: backend and frontend containers rebuild cleanly and restart.

- [ ] **Step 2: Verify the browser entry flow**

Check in a browser:
- `/` shows the Chinese login entry
- `/dashboard` is gated when not logged in
- successful login lands on the dashboard

- [ ] **Step 3: Verify the 401 fallback**

Trigger an expired-token or unauthorized case and confirm the frontend returns to `/` instead of staying on a broken page.

- [ ] **Step 4: Update the README if the workflow changed**

Document any new login or deployment expectations only if the test workflow changed in a user-visible way.

- [ ] **Step 5: Commit the smoke-test documentation**

```bash
git add README.md plans/055-login-auth-and-shell-gating.md
git commit -m "docs: record login gating workflow"
```
