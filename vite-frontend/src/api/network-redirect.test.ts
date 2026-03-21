import test from "node:test";
import assert from "node:assert/strict";

import { resolveUnauthorizedRedirect } from "./network-redirect.ts";

test("resolveUnauthorizedRedirect returns login entry for protected pages", () => {
  assert.equal(resolveUnauthorizedRedirect("/dashboard"), "/login");
  assert.equal(resolveUnauthorizedRedirect("/node"), "/login");
});

test("resolveUnauthorizedRedirect keeps the current entry page when already on login", () => {
  assert.equal(resolveUnauthorizedRedirect("/"), null);
  assert.equal(resolveUnauthorizedRedirect("/login"), null);
});
