import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const require = createRequire(import.meta.url);
const { trimConversation } = require("../lightsession-trimmer.js");

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(__dirname, "..", "fixtures");

async function fixture(name) {
  const data = await readFile(join(fixtureDir, name), "utf8");
  return JSON.parse(data);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assertLinearGraph(data) {
  const mapping = data.mapping;
  let cursor = data.root;
  const seen = new Set();
  while (cursor) {
    assert.ok(mapping[cursor], `missing node ${cursor}`);
    assert.equal(seen.has(cursor), false, `cycle at ${cursor}`);
    seen.add(cursor);
    const children = mapping[cursor].children || [];
    assert.ok(children.length <= 1, `unexpected branch at ${cursor}`);
    if (children[0]) {
      assert.equal(mapping[children[0]].parent, cursor);
    }
    cursor = children[0] || null;
  }
  assert.ok(seen.has(data.current_node), "current node remains reachable");
}

test("short chats are skipped and not mutated", async () => {
  const input = await fixture("short-chat.json");
  const before = clone(input);
  const trimmed = trimConversation(input, 20);

  assert.equal(trimmed.changed, false);
  assert.equal(trimmed.skipReason, "short");
  assert.equal(trimmed.visibleKept, 2);
  assert.equal(trimmed.visibleTotal, 2);
  assert.deepEqual(input, before);
});

test("long old chats keep only the latest visible turns and preserve metadata", async () => {
  const input = await fixture("long-old-chat.json");
  const before = clone(input);
  const trimmed = trimConversation(input, 4);

  assert.equal(trimmed.changed, true);
  assert.equal(trimmed.visibleKept, 4);
  assert.equal(trimmed.visibleTotal, 6);
  assert.equal(trimmed.data.metadata.preserve, true);
  assert.equal(trimmed.data.root, "root");
  assert.equal(trimmed.data.current_node, "a3");
  assert.deepEqual(Object.keys(trimmed.data.mapping), ["root", "u2", "a2", "u3", "a3"]);
  assertLinearGraph(trimmed.data);
  assert.deepEqual(input, before);
});

test("empty conversations are skipped explicitly", async () => {
  const input = await fixture("empty-new-conversation.json");
  const trimmed = trimConversation(input, 4);

  assert.equal(trimmed.changed, false);
  assert.equal(trimmed.skipReason, "empty");
});

test("shared conversations trim while preserving unrelated top-level fields", async () => {
  const input = await fixture("shared-conversation.json");
  const trimmed = trimConversation(input, 4);

  assert.equal(trimmed.changed, true);
  assert.equal(trimmed.data.share_id, "share-redacted");
  assert.equal(trimmed.data.current_node, "a3");
  assertLinearGraph(trimmed.data);
});

test("tool nodes attached to kept turns stay in the graph", async () => {
  const input = await fixture("tool-call-conversation.json");
  const trimmed = trimConversation(input, 3);

  assert.equal(trimmed.changed, true);
  assert.ok(trimmed.data.mapping.tool1);
  assert.equal(trimmed.data.mapping.tool1.parent, "a1");
  assert.equal(trimmed.data.mapping.tool1.children[0], "a2");
  assertLinearGraph(trimmed.data);
});

test("hidden system nodes do not count as visible turns", async () => {
  const input = await fixture("hidden-system-nodes.json");
  const trimmed = trimConversation(input, 2);

  assert.equal(trimmed.changed, true);
  assert.equal(trimmed.visibleKept, 2);
  assert.equal(trimmed.visibleTotal, 4);
  assertLinearGraph(trimmed.data);
});

test("thinking nodes attached to kept turns stay in the graph", async () => {
  const input = await fixture("thinking-nodes.json");
  const trimmed = trimConversation(input, 4);

  assert.equal(trimmed.changed, true);
  assert.ok(trimmed.data.mapping.thinking1);
  assert.equal(trimmed.data.mapping.thinking1.parent, "u2");
  assert.equal(trimmed.data.mapping.thinking1.children[0], "a2");
  assertLinearGraph(trimmed.data);
});

test("branched conversations fail open until branch semantics are proven", async () => {
  const input = await fixture("branched-conversation.json");
  const trimmed = trimConversation(input, 2);

  assert.equal(trimmed.changed, false);
  assert.equal(trimmed.skipReason, "branched-unknown");
});

test("malformed, cyclic, and unsupported shapes return explicit skip reasons", async () => {
  assert.equal(
    trimConversation(await fixture("malformed-conversation.json"), 2).skipReason,
    "malformed"
  );
  assert.equal(
    trimConversation(await fixture("cyclic-conversation.json"), 2).skipReason,
    "cyclic"
  );
  assert.equal(
    trimConversation(await fixture("unknown-future-shape.json"), 2).skipReason,
    "unsupported-shape"
  );
});
