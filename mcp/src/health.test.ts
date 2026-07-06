import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveCommand, isReadableFile, isReadableDir, isExecutableFile, validateConfig } from "./health.js";

// Hermetic env (from the `test` npm script):
//   GLIA_PSYCHE=test-fixtures/psyche.md
//   GBRAIN_SOURCE_DIR=test-fixtures/gbrain-source
//   GBRAIN_CMD=test-fixtures/gbrain-stub.sh

test("resolveCommand finds a bare command on PATH", () => {
  // node is on PATH wherever these tests run (locally + CI setup-node)
  assert.ok(resolveCommand("node") !== null);
});

test("resolveCommand returns null for a nonexistent absolute path", () => {
  assert.equal(resolveCommand("/nonexistent/definitely/not/here"), null);
});

test("resolveCommand resolves an executable relative path", () => {
  assert.equal(resolveCommand("test-fixtures/gbrain-stub.sh"), "test-fixtures/gbrain-stub.sh");
});

test("readability helpers agree with the fixture layout", () => {
  assert.equal(isReadableFile("test-fixtures/psyche.md"), true);
  assert.equal(isReadableFile("test-fixtures/nope.md"), false);
  assert.equal(isReadableDir("test-fixtures/gbrain-source"), true);
  assert.equal(isReadableDir("test-fixtures/psyche.md"), false); // a file is not a dir
  assert.equal(isExecutableFile("test-fixtures/gbrain-stub.sh"), true);
  assert.equal(isExecutableFile("test-fixtures/psyche.md"), false); // not executable
});

test("validateConfig reports a fully-healthy config from the fixtures", () => {
  const r = validateConfig(true);
  assert.equal(r.overall, "ok");
  assert.equal(r.psycheAvailable, true);
  assert.equal(r.retrievalAvailable, true);
  assert.equal(r.fatal, false);
  assert.equal(r.exitWorthy, false);
  assert.equal(r.checks.length, 3);
  const names = r.checks.map((c) => c.name).sort();
  assert.deepEqual(names, ["gbrainCmd", "gbrainSourceDir", "psyche"]);
});
