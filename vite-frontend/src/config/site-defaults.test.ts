import test from "node:test";
import assert from "node:assert/strict";

import { createDefaultSiteConfig } from "./site-defaults.ts";

test("createDefaultSiteConfig uses RealmFlow defaults", () => {
  const config = createDefaultSiteConfig();

  assert.equal(config.name, "RealmFlow");
  assert.equal(config.github_repo, "https://github.com/JackLuo1980/realm-flow");
});
