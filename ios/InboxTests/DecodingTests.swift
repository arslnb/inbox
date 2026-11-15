import XCTest

@testable import Inbox

// Every response the app reads, as the mock desk answers it (InboxTests/Fixtures), and the ways a newer or older desk may differ.
final class DecodingTests: XCTestCase {
  func testHealth() throws {
    let h: Health = try Fixture.decode("health")
    XCTAssertEqual(h.ok, true)
    XCTAssertEqual(h.version, "mock")
  }

  func testOverview() throws {
    let o: Overview = try Fixture.decode("overview")
    XCTAssertEqual(o.me, "me")
    XCTAssertEqual(o.aiAgent, "Claude")
    XCTAssertEqual(o.connectors.map(\.status), ["ok"])
    XCTAssertEqual(o.inflight?.total, 7)
    XCTAssertEqual(o.rateLimit?.remaining, 4870)
    XCTAssertNil(o.syncError)
    XCTAssertTrue(o.configErrors.isEmpty)
  }

  func testQueue() throws {
    let q: QueueView = try Fixture.decode("queue")
    XCTAssertEqual(q.inquiries.count, 2)
    XCTAssertEqual(q.sessions.count, 2)
    XCTAssertEqual([q.notes?.due.count, q.notes?.open.count, q.notes?.later.count], [1, 1, 1])
    XCTAssertEqual([q.inbox?.urgent.count, q.inbox?.standard.count, q.inbox?.fyi.count], [12, 13, 6])
    XCTAssertEqual(q.sections?.blocked.count, 11)
    XCTAssertEqual([q.hidden.count, q.cleared.count, q.resolved.count], [1, 10, 3])
    XCTAssertEqual(q.stacks?.count, 4)
    XCTAssertEqual(q.reviewing, 0)
    XCTAssertNil(q.paused)
    XCTAssertNil(q.firstPass)

    let first = try XCTUnwrap(q.inbox?.urgent.first)
    XCTAssertEqual(first.id, "acme/api#4127")
    XCTAssertEqual(first.shortRef, "api#4127")
    XCTAssertEqual(first.stage, "waiting for review")
    XCTAssertEqual(first.reason, "priya waits on your review; the planner's partial results")
    XCTAssertEqual(first.wakeOn, ["push"])
    XCTAssertEqual(first.new, true)
    XCTAssertEqual(first.waitingSince, "2026-11-13T04:22:37.843Z")
    XCTAssertNil(first.cta)

    // An issue has no stage key at all.
    let issue = try XCTUnwrap(q.inbox?.standard.first { $0.kind == "issue" })
    XCTAssertNil(issue.stage)
    XCTAssertFalse(issue.isPR)
    XCTAssertEqual(q.inbox?.urgent.compactMap(\.cta).sorted(), ["ready", "ready", "ready", "reply", "reply"])
    XCTAssertEqual(q.inbox?.urgent.first { $0.quick != nil }?.id, "oss/tinyhttp#212")
    XCTAssertEqual(q.sections?.blocked.map { $0.depth ?? 0 }, [0, 0, 0, 1, 2, 0, 0, 0, 1, 1, 2])
    XCTAssertEqual(q.cleared.first { $0.snoozeWhen != nil }?.snoozeWhen, "ci")

    XCTAssertEqual(q.inquiries[0].from, "Inbox coordinator")
    XCTAssertEqual(q.inquiries[0].options.count, 3)
    XCTAssertNil(q.inquiries[0].answer)
    XCTAssertEqual(q.sessions.map(\.status), ["active", "active"])
    XCTAssertEqual(q.sessions[0].actions, ["open"])
    XCTAssertEqual(q.stacks?["acme/api#4150"]?.line.count, 8)
  }

  func testInflight() throws {
    let v: InflightView = try Fixture.decode("inflight")
    XCTAssertEqual(v.rows.count, 8)
    XCTAssertEqual(v.rows.filter { $0.state == "open" }.count, 7)
    XCTAssertEqual(v.rows[0].waitsOn, "waits on a second look from dana")
    XCTAssertEqual(v.rows[0].note?.text?.hasPrefix("Pushed 4be71c2"), true)
    XCTAssertEqual(v.rows[1].card.stack?.id, "acme/api#4150")
    XCTAssertEqual(v.stacks?["acme/api#4150"]?.base, "main")
    XCTAssertEqual(v.coordinator?.on, true)
    XCTAssertEqual(v.coordinator?.url, "https://claude.ai/code/session_01MockCoordinator")
  }

  func testItem() throws {
    let d: ItemDetail = try Fixture.decode("item")
    XCTAssertEqual(d.card.id, "acme/api#4127")
    XCTAssertEqual(d.item?.additions, 62)
    XCTAssertEqual(d.item?.deletions, 7)
    XCTAssertEqual(d.item?.commentsTotal, 4)
    XCTAssertEqual(d.ai?.verdict, "look")
    XCTAssertEqual(d.ai?.risk, "medium")
    XCTAssertEqual(d.ai?.concerns?.count, 2)
    XCTAssertEqual(d.aiStale, false)
    XCTAssertEqual(d.activity.map(\.kind), ["commented", "mentioned", "pushed", "review_requested", "new"])
    XCTAssertEqual(d.activity[3].data?["reviewer"], .string("me"))
    XCTAssertEqual(d.activity[3].data?["codeowner"], .bool(false))
    XCTAssertNil(d.stack)
  }

  func testIssue() throws {
    let d: ItemDetail = try Fixture.decode("item-issue")
    XCTAssertEqual(d.card.kind, "issue")
    XCTAssertNil(d.card.stage)
    XCTAssertNil(d.ai)
    XCTAssertEqual(d.card.why, "assigned to you")
  }

  func testInquiry() throws {
    let q: Inquiry = try Fixture.decode("inquiry")
    XCTAssertEqual(q.id, "q1c0ffee")
    XCTAssertEqual(q.itemId, "me/notes-app#12")
    XCTAssertEqual(q.options.first?.answer, "Compact them in #12")
    XCTAssertEqual(q.links.count, 3)
    XCTAssertNil(q.answer)
    XCTAssertEqual(q.card?.id, "me/notes-app#12")
  }

  // A newer desk: enum values this app has never heard of, keys it doesn't know, a row it can't read. Nothing breaks the page.
  func testANewerDeskStillDecodes() throws {
    let json = """
      {
        "inbox": { "urgent": [
          { "id": "a/b#1", "kind": "discussion", "repo": "a/b", "number": 1, "title": "t", "stage": "in a merge train",
            "cta": "rebase", "status": "parked", "wake_on": ["deploy", "ci"], "section": "soon", "ci": "flaky", "novel": { "x": 1 } },
          { "id": "a/b#2", "kind": "pr" },
          "not a card",
          { "id": "a/b#3", "kind": "pr", "repo": "a/b", "number": 3, "title": "kept" }
        ], "later_today": [] },
        "sessions": [ { "id": "session:1", "kind": "cursor", "status": "active", "actions": ["teleport"] } ],
        "inquiries": null,
        "paused": { "who": "gemini", "why": "w" },
        "brand_new": true
      }
      """
    let q = try DeskJSON.decoder().decode(QueueView.self, from: Data(json.utf8))
    XCTAssertEqual(q.inbox?.urgent.map(\.id), ["a/b#1", "a/b#3"], "a row it can't read is skipped, the rest kept")
    XCTAssertEqual(q.inbox?.urgent[0].stage, "in a merge train")
    XCTAssertEqual(q.inbox?.urgent[0].cta, "rebase")
    XCTAssertNil(Words.cta["rebase"], "an unknown call to action has no label, so the row draws none")
    XCTAssertEqual(SnoozeOption.waits(q.inbox!.urgent[0]).map(\.until), ["ci"], "only what this app knows how to say")
    XCTAssertFalse(q.inbox!.urgent[0].active)
    XCTAssertTrue(q.inbox!.urgent[1].active, "no status reads as active")
    XCTAssertEqual(q.sessions.first?.kind, "cursor")
    XCTAssertTrue(q.inquiries.isEmpty)
    XCTAssertTrue(q.cleared.isEmpty, "a missing list is an empty one")
    XCTAssertEqual(Notices.of(Conditions(paused: q.paused)).first?.title, "AI reviews are paused")
  }

  // read_at is there, even null, only when the asker can pick the answer up.
  func testAnAnswersPickup() throws {
    let decode = { (s: String) in try DeskJSON.decoder().decode(Inquiry.Answer.self, from: Data(s.utf8)) }
    XCTAssertFalse(try decode(#"{"text":"yes","at":"2026-11-12T09:00:00.000Z","dismissed":false}"#).tracksPickup)
    let waiting = try decode(#"{"text":"yes","dismissed":false,"read_at":null}"#)
    XCTAssertTrue(waiting.tracksPickup)
    XCTAssertNil(waiting.readAt)
    XCTAssertEqual(try decode(#"{"text":"","dismissed":true,"read_at":"2026-11-12T09:00:00Z"}"#).readAt, "2026-11-12T09:00:00Z")
  }

  func testBothTimeFormats() {
    let withMillis = Words.date("2026-11-12T09:00:00.000Z")
    XCTAssertNotNil(withMillis)
    XCTAssertEqual(withMillis, Words.date("2026-11-12T09:00:00Z"))
    XCTAssertNil(Words.date("yesterday"))
    XCTAssertNil(Words.date(nil))
  }

  func testTheFontsAreBundled() {
    XCTAssertNotNil(UIFont(name: Typeface.sans.name, size: 12), "Instrument Sans is registered (UIAppFonts)")
    XCTAssertNotNil(UIFont(name: Typeface.mono.name, size: 12), "JetBrains Mono is registered (UIAppFonts)")
    XCTAssertEqual(Typeface.sans.font(15, weight: 650).familyName, "Instrument Sans")
  }

  // GET /api/review/:id, whole: someone's PR with a walk-through, diagrams and every newer part of the AI review.
  func testAReview() throws {
    let r: ReviewView = try Fixture.decode("review")
    XCTAssertEqual(r.card?.id, "acme/worker#879")
    XCTAssertEqual(r.item?.state, "open")
    XCTAssertEqual(r.item?.draft, false)
    XCTAssertEqual(r.item?.headOid, "0000000000000000000000000000021f407ad6bf")
    XCTAssertEqual(r.diffHead, r.item?.headOid)
    XCTAssertEqual(r.item?.body?.hasPrefix("The scheduler both leased jobs and dispatched them"), true)
    XCTAssertEqual(r.item?.changedFiles, 31)
    XCTAssertEqual(r.item?.reviewRequests.map(\.reviewer), ["ml-team"])
    XCTAssertEqual(r.item?.reviewRequests.map(\.type), ["team"])
    XCTAssertEqual(r.item?.reviews.map(\.state), ["commented"])
    XCTAssertNil(r.filesError)
    XCTAssertNil(r.aiError)
    XCTAssertNil(r.aiJob)
    XCTAssertEqual(r.aiStale, false)
    XCTAssertEqual(r.generating, false)
    XCTAssertEqual(r.approve?.ok, true)
    XCTAssertNil(r.cantApprove)
    XCTAssertEqual(r.activity.first?.kind, "reviewed")
    XCTAssertNil(r.stack)
    XCTAssertTrue(r.asks.isEmpty)
    XCTAssertNil(r.merge)
    XCTAssertNil(r.checksError)
    XCTAssertNil(r.readingError)

    XCTAssertEqual(r.files.count, 31)
    XCTAssertEqual(r.files[0].path, "src/split-the-scheduler-into-lease.ts")
    XCTAssertEqual([r.files[0].status, r.files[0].previousPath], ["modified", nil])
    XCTAssertEqual([r.files[1].additions, r.files[1].deletions], [37, 5])
    XCTAssertFalse(Mirror(reflecting: r.files[0]).children.contains { $0.label == "patch" }, "a file's patch is never held: its hunks are in order")

    let order = try XCTUnwrap(r.order)
    XCTAssertEqual(order.ranked, true)
    XCTAssertEqual([order.chunks.count, order.unread.count, order.skipped.count, order.rest.count], [20, 5, 6, 0])
    XCTAssertEqual(order.notes, [0])
    XCTAssertEqual(order.beyond?.count, 11)
    let h = order.chunks[0]
    XCTAssertEqual(h.id, "h1")
    XCTAssertEqual([h.path, h.level, h.why], ["src/split-the-scheduler-into-lease.ts", "look", "lease renewal and fencing token"])
    XCTAssertEqual([h.file, h.rank, h.additions, h.deletions], [0, 1, 4, 2])
    XCTAssertEqual(h.header, #"@@ -8,8 +8,10 @@ import { log } from "./log.ts";"#)
    XCTAssertEqual(h.patch?.hasPrefix("@@ -8,8 +8,10 @@"), true)
    XCTAssertEqual([h.notes, h.looks], [[0], [0]])
    XCTAssertEqual(order.unread.first?.level, "unread")
    XCTAssertEqual(order.skipped.first?.level, "skip")
    let steps = try XCTUnwrap(order.steps)
    XCTAssertEqual(steps.map(\.title), ["Leases and the fencing token", "Dispatch reads from a channel", "Errors, retries and config"])
    XCTAssertEqual(steps.map(\.diagram), ["d1", "d2", nil])
    XCTAssertEqual(steps.map(\.check), ["A renewal after the lease expired is refused, not extended.", "A full channel slows leasing instead of dropping jobs.", ""])
    XCTAssertEqual(steps[0].note?.hasPrefix("Lease ships first"), true)
    XCTAssertNil(steps[1].note)
    XCTAssertEqual(steps[0].hunks.map(\.id), ["h2", "h3", "h1"])
    XCTAssertEqual(steps[0].hunks[0].patch?.hasPrefix("@@"), true, "a step's hunks are whole, not refs")

    let ai = try XCTUnwrap(r.ai)
    XCTAssertEqual([ai.verdict, ai.risk, ai.model], ["look", "medium", "claude-opus-5[1m]"])
    XCTAssertEqual(ai.headOid, r.item?.headOid)
    XCTAssertNotNil(Words.date(ai.at))
    XCTAssertEqual(ai.riskReasons.map(\.factor), ["concurrency", "deploy"])
    XCTAssertEqual(ai.intent?.fit, "partial")
    XCTAssertEqual(ai.intent?.goal?.hasPrefix("Splits the scheduler into Lease and Dispatch"), true)
    XCTAssertEqual(ai.intent?.gap, "Also renames the retry config keys, which the description doesn't mention.")
    XCTAssertEqual(ai.intent?.stack, "")
    XCTAssertEqual(ai.notes.count, 1)
    XCTAssertEqual([ai.notes[0].path, ai.notes[0].side], ["src/split-the-scheduler-into-lease.ts", "new"])
    XCTAssertEqual(ai.notes[0].line, 12)
    XCTAssertEqual(ai.notes[0].body?.hasPrefix("The behaviour change:"), true)
    XCTAssertEqual([ai.look.first?.line, ai.look.first?.end], [12, 14])
    XCTAssertEqual(ai.look.first?.why, "the fencing token must be checked before the write")
    XCTAssertEqual([ai.interfaces.first?.name, ai.interfaces.first?.kind, ai.interfaces.first?.change], ["Lease.renew()", "function", "added"])
    XCTAssertEqual(ai.interfaces.first?.breaking, false)
    XCTAssertEqual(ai.improvements.first?.body?.hasPrefix("Pass the token into `report()`"), true)
    XCTAssertEqual(ai.guide?.steps.count, 3)
    XCTAssertEqual(ai.guide?.steps[0].hunks.map(\.id), ["h2", "h3", "h1"])

    XCTAssertEqual(ai.diagrams.map(\.id), ["d1", "d2"])
    XCTAssertEqual(ai.diagrams[0].title, "Who owns a job now")
    XCTAssertEqual(ai.diagrams[0].caption?.hasPrefix("Dispatch never writes the jobs table"), true)
    XCTAssertNotNil(ai.diagrams[0].source)
    guard case .flow(let flow)? = ai.diagrams[0].graph else { return XCTFail("d1 is a flowchart") }
    XCTAssertEqual(flow.direction, "LR")
    XCTAssertEqual(flow.nodes.map(\.label), ["Worker", "Dispatch", "Lease", "jobs table", "Old scheduler"])
    XCTAssertEqual(flow.nodes.map(\.mark), [nil, "new", "new", nil, "removed"])
    XCTAssertEqual(flow.nodes[3].shape, "store")
    XCTAssertEqual(flow.edges.count, 6)
    XCTAssertEqual([flow.edges[0].from, flow.edges[0].to], ["w", "d"])
    XCTAssertTrue(flow.groups.isEmpty)
    guard case .sequence(let seq)? = ai.diagrams[1].graph else { return XCTFail("d2 is a sequence") }
    XCTAssertEqual(seq.participants.map(\.label), ["Dispatch", "Lease", "jobs table"])
    XCTAssertEqual(seq.messages.count, 7)
    XCTAssertEqual([seq.messages[0].text, seq.messages[2].text], ["lease()", "job + token"])
    XCTAssertEqual([seq.messages[0].reply, seq.messages[2].reply], [false, true])
    XCTAssertEqual(seq.notes.count, 1)

    let checks = try XCTUnwrap(r.checks)
    XCTAssertEqual(checks.line, "CI passing · 11 checks")
    XCTAssertEqual(checks.failing, false)
    XCTAssertEqual(checks.list.count, 11)
    XCTAssertEqual([checks.list[1].name, checks.list[1].state], ["codecov/patch", "passing"])
    XCTAssertEqual(checks.list[1].optional, true)
    XCTAssertEqual(checks.list.last?.state, "skipped")
    XCTAssertEqual(r.reviewers?.line, "Waiting on @ml-team")
    XCTAssertEqual(r.reviewers?.changes, false)
    XCTAssertEqual(r.reviewers?.list.map(\.who), ["@ml-team", "priya"])
    XCTAssertEqual(r.reviewers?.list.map(\.state), ["asked", "commented"])
  }

  // Your own PR: not yours to approve, and what reviewers said, those waiting on you first.
  func testAReviewOfYourOwnPR() throws {
    let r: ReviewView = try Fixture.decode("review-own")
    XCTAssertEqual(r.card?.mine, true)
    XCTAssertEqual(r.approve?.ok, false)
    XCTAssertEqual(r.approve?.reason, "it's your PR")
    XCTAssertNil(r.ai)
    XCTAssertEqual(r.order?.ranked, false, "no ranking: every hunk, file by file")
    XCTAssertNil(r.order?.steps)
    XCTAssertEqual(r.reviewers?.line, "Waiting on kai")
    XCTAssertNil(r.conversationError)
    XCTAssertEqual(r.reading, false)
    XCTAssertEqual(r.conversation.count, 5)
    let first = try XCTUnwrap(r.conversation.first)
    XCTAssertEqual(first.id, "PRRT_tomb", "what a reply goes to")
    XCTAssertEqual(first.kind, "thread")
    XCTAssertEqual([first.path, first.line.map(String.init)], ["src/sync/merge.ts", "88"])
    XCTAssertEqual([first.outdated, first.resolved, first.waitingOnYou], [false, false, true])
    XCTAssertEqual(first.comments.map(\.author), ["azulus"])
    XCTAssertEqual(first.comments.first?.bot, false)
    XCTAssertEqual(first.comments.first?.url, "https://github.com/me/notes-app/pull/12#c1")
    XCTAssertEqual(first.comments.first?.body?.hasPrefix("Tombstones never go away here."), true)
    XCTAssertEqual(first.take?.gist, "Tombstones are never compacted, so every sync ships all of them")
    XCTAssertEqual(first.take?.take?.hasPrefix("Valid concern:"), true)
    XCTAssertEqual(first.take?.commentId, "c1")
    XCTAssertNotNil(Words.date(first.take?.at))
    XCTAssertTrue(r.conversation.filter { $0.waitingOnYou == true }.count < r.conversation.count, "those waiting on you, then the rest")
    let steps: ReviewView = try Fixture.decode("review-steps")
    XCTAssertEqual(steps.conversation.first?.side, "new")
    XCTAssertEqual(steps.order?.steps?.count, 4)
    XCTAssertTrue(steps.ai?.diagrams.isEmpty == true)
    XCTAssertNil(steps.ai?.intent, "a review written before its newer parts")
  }

  // A desk that lacks what's optional, or sends what this app doesn't know: the page still reads, less only that part.
  func testAReviewFromAnotherDesk() throws {
    let r: ReviewView = try Fixture.decode("review-lean")
    XCTAssertEqual(r.item?.headOid, "b2")
    XCTAssertNil(r.item?.body)
    XCTAssertTrue(r.item?.reviewRequests.isEmpty == true)
    XCTAssertEqual(r.files.map(\.path), ["a.ts", nil])
    XCTAssertNil(r.diffHead)
    XCTAssertEqual(r.filesError, "the diff is too large for GitHub to show")
    XCTAssertEqual(r.order?.chunks.map(\.id), ["h1"], "a hunk it can't read is dropped, not the page")
    XCTAssertNil(r.order?.chunks[0].patch)
    XCTAssertNil(r.order?.chunks[0].level, "no ranking for this commit")
    XCTAssertNil(r.order?.ranked)
    XCTAssertNil(r.order?.steps)
    XCTAssertNil(r.order?.beyond)
    XCTAssertEqual(r.order?.rest.map(\.why), ["lockfile or generated"])
    XCTAssertTrue(r.order?.rest.first?.hunks.isEmpty == true)
    XCTAssertNil(r.ai?.verdict)
    XCTAssertNil(r.ai?.intent)
    XCTAssertTrue(r.ai?.notes.isEmpty == true)
    XCTAssertEqual(r.ai?.diagrams.map(\.id), ["d1", "d2"])
    guard case .other("gantt")? = r.ai?.diagrams[0].graph else { return XCTFail("a kind of diagram this app doesn't know is kept as that") }
    XCTAssertNil(r.ai?.diagrams[1].graph)
    XCTAssertEqual(r.aiError, "Claude Code is logged out")
    XCTAssertEqual([r.aiJob?.state, r.aiJob?.error, r.aiJob?.head], ["failed", "timed out", "b2"])
    XCTAssertEqual(r.aiJob?.attempts, 3)
    XCTAssertNil(r.aiJob?.retryAt)
    XCTAssertNil(r.aiStale)
    XCTAssertNil(r.generating)
    XCTAssertEqual(r.approve?.reason, "you approved this commit")
    XCTAssertEqual(r.asks.map(\.id), ["k1", "k2"])
    XCTAssertNil(r.asks[0].answer)
    XCTAssertNil(r.asks[0].lines)
    XCTAssertEqual(r.asks[1].answer?.text, "Yes.")
    XCTAssertEqual([r.asks[1].lines?.path, r.asks[1].lines?.side, r.asks[1].lines?.head], ["a.ts", "new", "b2"])
    XCTAssertEqual(r.asks[1].lines?.note, true)
    XCTAssertNil(r.checks)
    XCTAssertEqual(r.checksError, "GitHub answered 502")
    XCTAssertEqual(r.reviewers?.changes, true)
    XCTAssertEqual(r.reviewers?.list.map(\.who), ["kofi", nil])
    XCTAssertEqual(r.merge, "Merge conflict with main")
    XCTAssertEqual(r.conversation.map(\.id), ["a"], "a conversation it can't read is dropped, not the page")
    XCTAssertEqual(r.conversation[0].comments.map(\.id), ["c"])
    XCTAssertEqual(r.conversation[0].side, "sideways", "an enum stays the string it came as")
    XCTAssertEqual(r.conversationError, "GitHub said no")
    XCTAssertEqual(r.readingError, "it timed out")
    XCTAssertTrue(r.activity.isEmpty)

    let empty = try DeskJSON.decoder().decode(ReviewView.self, from: Data("{}".utf8))
    XCTAssertNil(empty.card)
    XCTAssertNil(empty.order)
    XCTAssertNil(empty.reviewers)
    XCTAssertTrue(empty.files.isEmpty && empty.conversation.isEmpty && empty.asks.isEmpty)
  }

  func testReviewers() throws {
    let all = try DeskJSON.decoder().decode([Reviewer].self, from: try Fixture.data("reviewers"))
    XCTAssertEqual(all.map(\.login), ["dana", "sam"])
    XCTAssertEqual(all.map(\.id), ["U_dana", "U_sam"])
    XCTAssertEqual(all.first?.name, "Dana Okafor")
    XCTAssertEqual(all.map(\.suggested), [true, true])
    XCTAssertEqual(all.map(\.team), [false, false])
  }

  // What the actions are offered by: the desk's own allowances on each card, and the commit an item was read at.
  func testACardsAllowancesAndAnItemsCommit() throws {
    let q: QueueView = try Fixture.decode("queue")
    let rows = (q.inbox?.urgent ?? []) + (q.inbox?.standard ?? []) + (q.inbox?.fyi ?? [])
    let card = { (id: String) in try XCTUnwrap(rows.first { $0.id == id }) }
    XCTAssertEqual(try card("acme/api#4127").actions, ["request_changes", "unrequest"])
    XCTAssertEqual(try card("acme/worker#875").actions, ["close", "draft", "rerequest", "merge"])
    XCTAssertEqual(try card("acme/web#2303").actions, ["close", "ready"])
    XCTAssertEqual(try card("acme/worker#860").actions, ["close"], "an issue")
    XCTAssertEqual(try card("acme/web#2303").cta, "ready")
    let item: ItemDetail = try Fixture.decode("item")
    XCTAssertEqual(item.item?.headOid, "000000000000000000000000000009f6a052cc6f")
  }

  // What a PR depends on, as the review's Depends line says it (Review.tsx's depFacts()).
  func testWhatAPRDependsOn() throws {
    let q: QueueView = try Fixture.decode("queue")
    let all = (q.inbox?.urgent ?? []) + (q.inbox?.standard ?? []) + (q.inbox?.fyi ?? []) + (q.sections?.blocked ?? [])
    let card = { (id: String) in try XCTUnwrap(all.first { $0.id == id }, "no \(id)") }
    XCTAssertEqual(ReviewState.depends(try card("acme/billing#2302")), "blocked by api#1294 (through billing#2300) · blocks billing#2303")
    XCTAssertEqual(ReviewState.depends(try card("acme/api#1294")), "blocks billing#2298, billing#2299 and 4 more")
    XCTAssertEqual(ReviewState.depends(try card("acme/api#4127")), "")
    XCTAssertEqual(Words.andMore(["a"]), "a")
    XCTAssertEqual(Words.andMore(["a", "b"]), "a and b")
    XCTAssertEqual(Words.andMore(["a", "b", "c"]), "a, b and 1 more")
  }

  // view.ts's handsOff(): through its review, not a draft, and somebody asked (or nobody needed).
  func testWhatIsHandedOffForMerge() throws {
    let card = { (more: String) in
      try DeskJSON.decoder().decode(Card.self, from: Data(#"{"id":"a/b#1","kind":"pr","repo":"a/b","number":1,"title":"t"\#(more)}"#.utf8))
    }
    XCTAssertTrue(try card(#","review":"approved""#).handsOff)
    XCTAssertTrue(try card(#","review":"none""#).handsOff)
    XCTAssertFalse(try card(#","review":"required""#).handsOff)
    XCTAssertFalse(try card(#","review":"changes_requested""#).handsOff)
    XCTAssertFalse(try card(#","review":"approved","draft":true"#).handsOff)
    XCTAssertFalse(try card(#","review":"none","cta":"reviewers""#).handsOff, "add reviewers first")
    XCTAssertTrue(try card(#","review":"none","cta":"reviewers","review_optional":true"#).handsOff, "its repo needs no review")
    XCTAssertFalse(try card(#","review":"approved","inflight":true"#).handsOff, "in Merging already: Back to desk")
    let issue = try DeskJSON.decoder().decode(Card.self, from: Data(#"{"id":"a/b#2","kind":"issue","repo":"a/b","number":2,"title":"t"}"#.utf8))
    XCTAssertFalse(issue.handsOff)
  }

  // What reviewers said, as the mock's reply-only PR has it: read and unread, on a line and on the PR, outdated, resolved.
  func testConversations() throws {
    let review: ReviewView = try Fixture.decode("review-own")
    let all = Dictionary(uniqueKeysWithValues: review.conversation.map { ($0.id, $0) })
    XCTAssertEqual(review.conversation.filter { $0.waitingOnYou == true }.map(\.id), ["PRRT_tomb", "IC_freeze"])
    XCTAssertEqual(all["PRRT_tomb"]?.take?.gist, "Tombstones are never compacted, so every sync ships all of them")
    let name = try XCTUnwrap(all["PRRT_name"])
    XCTAssertNil(name.take, "nobody waits on it, so your agent didn't read it")
    XCTAssertEqual(name.resolved, true)
    XCTAssertEqual(name.comments.map(\.author), ["kai", "me"])
    let bot = try XCTUnwrap(all["PRRT_bot"])
    XCTAssertEqual(bot.outdated, true)
    XCTAssertNil(bot.line)
    XCTAssertEqual(bot.comments.first?.bot, true)
    XCTAssertEqual(Words.place(bot), "src/sync/merge.ts, outdated")
    XCTAssertEqual(all["PRR_kai"]?.kind, "review")
    XCTAssertEqual(review.reading, false)
    XCTAssertNil(review.readingError)

    // A desk that says less: a conversation is its id, and what it couldn't read is said.
    let lean = try DeskJSON.decoder().decode(
      ReviewView.self, from: Data(#"{"conversation":[{"id":"x"},{"comments":[]}],"conversation_error":"rate limited","reading":true,"reading_error":"timed out"}"#.utf8))
    XCTAssertEqual(lean.conversation.map(\.id), ["x"])
    XCTAssertTrue(lean.conversation[0].comments.isEmpty)
    XCTAssertEqual([lean.conversationError, lean.readingError], ["rate limited", "timed out"])
    XCTAssertEqual(lean.reading, true)
  }
}
