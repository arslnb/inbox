// Records the mock desk (web/mock/server.ts) into ios/Inbox/Demo.json: every answer the iPhone app asks for, which its
// test mode replays with no desk. ios/testflight.sh runs it before each upload (npm run ios:demo).
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { field, isRecord, str } from "../src/narrow.ts";

const root = join(import.meta.dirname, "..");
const PORT = 47859;
const base = `http://127.0.0.1:${PORT}`;
const mock = spawn(process.execPath, ["--disable-warning=ExperimentalWarning", join(root, "web/mock/server.ts")], {
  env: { ...process.env, MOCK_PORT: String(PORT), MOCK_NO_POLL: "1" },
  stdio: "ignore",
});

async function get(path: string): Promise<unknown> {
  const res = await fetch(base + path);
  return res.ok ? res.json() : undefined;
}

async function up() {
  for (let i = 0; i < 100; i++) {
    if (
      await fetch(base + "/health").then(
        (r) => r.ok,
        () => false,
      )
    )
      return;
    await new Promise((r) => {
      setTimeout(r, 100);
    });
  }
  throw new Error("the mock didn't start");
}

// Every item id and question id the lists name.
function ids(v: unknown, items: Set<string>, asks: Set<string>, inQuestions = false): void {
  if (Array.isArray(v)) {
    for (const x of v) ids(x, items, asks, inQuestions);
    return;
  }
  if (!isRecord(v)) return;
  for (const [k, x] of Object.entries(v)) {
    const s = str(x);
    if (s && (k === "id" || k === "item_id") && /^[\w.-]+\/[\w.-]+#\d+$/.test(s)) items.add(s);
    else if (s && k === "id" && inQuestions) asks.add(s);
    ids(x, items, asks, k === "inquiries");
  }
}

// No claude.ai session to watch in test mode: the link would lead nowhere.
function quiet(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(quiet);
  if (!isRecord(v)) return v;
  return Object.fromEntries(
    Object.entries(v).map(([k, x]) => [k, typeof x === "string" && x.startsWith("https://claude.ai/") ? null : quiet(x)]),
  );
}

const seg = (id: string) => encodeURIComponent(id);

try {
  await up();
  const routes: Record<string, unknown> = {};
  for (const path of ["/health", "/api/overview", "/api/setup", "/api/queue", "/api/inflight", "/api/asks"]) routes[path] = await get(path);
  const items = new Set<string>();
  const asks = new Set<string>();
  for (const path of ["/api/queue", "/api/inflight", "/api/overview"]) ids(routes[path], items, asks);
  for (const id of [...items].sort()) {
    const item = await get(`/api/item?id=${seg(id)}`);
    if (item === undefined) continue;
    routes[`/api/item?id=${id}`] = item;
    if (field(field(item, "card"), "kind") === "issue") continue;
    const review = await get(`/api/review/${seg(id)}?ahead=1`);
    if (review !== undefined) routes[`/api/review/${id}`] = review;
    const reviewers = await get(`/api/reviewers/${seg(id)}?q=`);
    if (reviewers !== undefined) routes[`/api/reviewers/${id}`] = reviewers;
  }
  for (const id of [...asks].sort()) {
    const inquiry = await get(`/api/inquiries/${seg(id)}`);
    if (inquiry !== undefined) routes[`/api/inquiries/${id}`] = inquiry;
  }
  const out = { recorded_at: new Date().toISOString(), routes: quiet(routes) };
  writeFileSync(join(root, "ios/Inbox/Demo.json"), JSON.stringify(out) + "\n");
  console.log(`ios/Inbox/Demo.json: ${Object.keys(routes).length} answers, ${items.size} items, ${asks.size} questions`);
} finally {
  mock.kill();
}
