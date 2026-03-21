import test from "node:test";
import assert from "node:assert/strict";

import { resolvePoweredByBrand } from "./version-footer-brand.ts";

test("resolvePoweredByBrand keeps RealmFlow branding for the default repository", () => {
  assert.equal(
    resolvePoweredByBrand("https://github.com/JackLuo1980/realm-flow"),
    "RealmFlow",
  );
});

test("resolvePoweredByBrand falls back to RealmFlow branding for unknown repositories", () => {
  assert.equal(resolvePoweredByBrand("https://example.com/other"), "RealmFlow");
});
