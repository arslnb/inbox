import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { checkoutFor, prCheckout } from "../src/checkout.ts";
import { failure, run } from "./helpers/run.ts";
import { posix } from "./helpers/platform.ts";

// Run from a git hook (pre-push), GIT_DIR and the like point every git here at the desk's own repo.
for (const k of Object.keys(process.env)) if (k.startsWith("GIT_")) delete process.env[k];
const git = (cwd: string, ...args: string[]) =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main", ...args], {
    cwd,
    encoding: "utf8",
  }).trim();

// GitHub as a local repo (main, and a PR head only under refs/pull/7/head), and your clone of it before the PR was pushed.
function repos() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "desk-checkout-")));
  const hub = path.join(root, "hub");
  fs.mkdirSync(hub);
  git(hub, "init", "-q");
  fs.writeFileSync(path.join(hub, "app.ts"), "export const limit = 10;\n");
  git(hub, "add", ".");
  git(hub, "commit", "-qm", "main");
  const clone = path.join(root, "code", "api");
  git(root, "clone", "-q", hub, clone);
  git(hub, "checkout", "-qb", "pr");
  fs.writeFileSync(path.join(hub, "app.ts"), "export const limit = 100;\n");
  git(hub, "commit", "-qam", "pr");
  const head = git(hub, "rev-parse", "HEAD");
  git(hub, "update-ref", "refs/pull/7/head", head);
  git(hub, "checkout", "-q", "main");
  const home = path.join(root, "home");
  fs.mkdirSync(home);
  return { root, hub, clone, head, home };
}

test("a PR's head is checked out from your clone, fetched when the clone lacks it, and your clone is left as it was", posix, async () => {
  const r = repos();
  const before = [git(r.clone, "for-each-ref"), git(r.clone, "worktree", "list"), git(r.clone, "status", "--porcelain")];
  const item = { repo: "acme/api", number: 7, head_oid: r.head };
  const c = await run(prCheckout(r.home, r.clone, item, r.hub));
  assert.equal(fs.readFileSync(path.join(c.dir, "app.ts"), "utf8"), "export const limit = 100;\n", "the PR's code, not main's");
  assert.equal(git(c.dir, "rev-parse", "HEAD"), r.head);
  assert.deepEqual(
    [git(r.clone, "for-each-ref"), git(r.clone, "worktree", "list"), git(r.clone, "status", "--porcelain")],
    before,
    "no ref, worktree or file of yours changed",
  );

  const again = await run(prCheckout(r.home, r.clone, item, path.join(r.root, "nowhere")));
  assert.notEqual(again.dir, c.dir, "a checkout per review; the head is already fetched, so no remote is asked");
  await run(c.done);
  await run(again.done);
  assert.ok(!fs.existsSync(c.dir) && !fs.existsSync(again.dir), "removed once it's done");
  fs.rmSync(r.root, { recursive: true });
});

test("with no clone of yours, the desk clones it from GitHub (blobless) and checks the head out from that", posix, async () => {
  const r = repos();
  const item = { repo: "acme/api", number: 7, head_oid: r.head };
  const c = await run(checkoutFor(r.home, item, () => null, r.hub));
  assert.equal(fs.readFileSync(path.join(c.dir, "app.ts"), "utf8"), "export const limit = 100;\n");
  assert.ok(!fs.existsSync(path.join(r.home, "repos", "acme__api.git", "objects", "info", "alternates")), "its own, borrowing nothing");
  await run(c.done);
  fs.rmSync(r.root, { recursive: true });
});

test("a head that can't be fetched is why there's no review, in words its review shows", posix, async () => {
  const r = repos();
  const gone = await failure(
    checkoutFor(r.home, { repo: "acme/api", number: 8, head_oid: "0".repeat(40) }, () => r.clone, path.join(r.root, "nowhere")),
  );
  assert.equal(gone._tag, "NoCheckout");
  assert.match(gone.message, new RegExp(`^couldn't check out this PR's head from your clone at ${r.clone}: `));
  fs.rmSync(r.root, { recursive: true });
});
