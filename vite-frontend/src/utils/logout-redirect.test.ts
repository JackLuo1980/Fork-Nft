import test from "node:test";
import assert from "node:assert/strict";

import { resolveLogoutRedirect } from "./logout-redirect.ts";

test("resolveLogoutRedirect sends users back to login from protected pages", () => {
  assert.equal(resolveLogoutRedirect("/dashboard"), "/login");
  assert.equal(resolveLogoutRedirect("/profile"), "/login");
});

test("resolveLogoutRedirect keeps entry pages unchanged", () => {
  assert.equal(resolveLogoutRedirect("/"), null);
  assert.equal(resolveLogoutRedirect("/login"), null);
});
