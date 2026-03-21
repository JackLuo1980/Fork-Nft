import test from "node:test";
import assert from "node:assert/strict";

import { resolveEntryRedirect } from "./route-guard.ts";

test("resolveEntryRedirect sends authenticated users from login entry routes to dashboard", () => {
  assert.equal(resolveEntryRedirect(true, "/"), "/dashboard");
  assert.equal(resolveEntryRedirect(true, "/login"), "/dashboard");
});

test("resolveEntryRedirect sends unauthenticated users away from protected routes", () => {
  assert.equal(resolveEntryRedirect(false, "/dashboard"), "/");
  assert.equal(resolveEntryRedirect(false, "/node"), "/");
});

test("resolveEntryRedirect keeps users on the current entry route when no redirect is needed", () => {
  assert.equal(resolveEntryRedirect(false, "/"), null);
  assert.equal(resolveEntryRedirect(false, "/login"), null);
});
