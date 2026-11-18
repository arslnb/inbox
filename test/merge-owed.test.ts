// Someone else's PR you approved whose author has no say on the repo (a fork's contributor): they can't merge it, so the
// merge is yours. Approving doesn't resolve it, Done doesn't hide it, and its row offers Hand off for merge.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mergeOwed, waitsOf } from "../src/stage.ts";
import { reviewAsk, setup } from "./helpers/desk.ts";
import { hoursAgo } from "./helpers/items.ts";
import { run, runSync } from "./helpers/run.ts";
import { refuseWrites } from "./helpers/writer.ts";
import type { Item } from "../src/types.ts";

const approvedByMe = (n: number, o: Partial<Item> = {}) =>
  reviewAsk(n, {
    author: "outsider",
    review_requests: [],
    reviews: [{ author: "me", author_bot: false, state: "approved", at: hoursAgo(1), commit: "h4", trusted: true }],
    ci: "green",
    review_decision: "approved",
    mergeable: "clean",
    merge_method: "SQUASH",
    head_oid: "h4",
    author_can_merge: false,
    ...o,
  });

test("the merge is yours: approved by you, its author can't merge it, nobody holds it", () => {
  assert.equal(mergeOwed(approvedByMe(1), "me"), true);
  assert.equal(mergeOwed(approvedByMe(1, { author_can_merge: true }), "me"), false, "a collaborator merges their own");
  const { author_can_merge: _, ...old } = approvedByMe(1);
  assert.equal(mergeOwed(old, "me"), false, "stored before it was fetched");
  assert.equal(mergeOwed(approvedByMe(1, { draft: true }), "me"), false, "a draft");
  assert.equal(mergeOwed(approvedByMe(1, { can_merge: false }), "me"), false, "you can't merge it either");
  assert.equal(mergeOwed(approvedByMe(1, { review_decision: "required" }), "me"), false, "GitHub wants another approval");
  const held = approvedByMe(1);
  held.reviews.push({ author: "dana", author_bot: false, state: "changes_requested", at: hoursAgo(0), commit: "h4" });
  assert.equal(mergeOwed(held, "me"), false, "someone asked for changes");
  const changed = approvedByMe(1);
  changed.reviews.push({ author: "me", author_bot: false, state: "changes_requested", at: hoursAgo(0), commit: "h4" });
  assert.equal(mergeOwed(changed, "me"), false, "your latest verdict isn't an approval");
  const o = { mine: false, unasked: false, askedYou: false, waitingOn: [] };
  assert.equal(waitsOf(approvedByMe(1), "me", o), "is yours to merge: outsider can't");
  assert.equal(waitsOf(approvedByMe(1, { author_can_merge: true }), "me", o), "is approved, for outsider to merge");
});

test("a merge you owe isn't resolved by your approval, Done doesn't hide it, and its row hands it off for merge", async (c) => {
  const t = await setup([approvedByMe(66), approvedByMe(67, { author_can_merge: true })], { desk: { writer: refuseWrites() } });
  c.after(t.cleanup);
  const route = t.gh.route;
  t.gh.route = (q) => (q.includes("review-requested:@me") ? ["acme/api#66", "acme/api#67"] : route(q)); // as reviewed-by:@me lists them
  await run(t.desk.sync());
  const card = (ref: string) => runSync(t.desk.item(ref)).card;
  assert.equal(card("api#66").resolved, null);
  assert.equal(card("api#67").resolved, "you approved", "a collaborator's: your part is done");
  assert.equal(card("api#66").cta, "handoff");
  assert.ok(card("api#66").actions?.includes("merge"), "More merges it now");
  runSync(t.desk.act("api#66", "done"));
  await run(t.desk.sync());
  assert.equal(card("api#66").done_at, undefined, "still on your desk after Done");
  runSync(t.desk.act("api#66", "inflight"));
  assert.equal(card("api#66").inflight, true, "handed off: Merging has it");
});
