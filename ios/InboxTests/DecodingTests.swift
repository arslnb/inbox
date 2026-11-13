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

  // GET /api/review/:id?ahead=1: only the conversation and the approval are read; the diff that rides along is skipped.
  func testAReviewsConversationAndApproval() throws {
    let r: ReviewRead = try Fixture.decode("review")
    XCTAssertEqual(r.approve?.ok, false)
    XCTAssertEqual(r.approve?.reason, "it's your PR")
    XCTAssertNil(r.conversationError)
    XCTAssertEqual(r.reading, false)
    XCTAssertEqual(r.conversation.count, 5)
    let first = try XCTUnwrap(r.conversation.first)
    XCTAssertEqual(first.id, "PRRT_tomb", "what a reply goes to")
    XCTAssertEqual(first.kind, "thread")
    XCTAssertEqual([first.path, first.line.map(String.init)], ["src/sync/merge.ts", "88"])
    XCTAssertEqual(first.waitingOnYou, true)
    XCTAssertEqual(first.comments.map(\.author), ["azulus"])
    XCTAssertEqual(first.comments.first?.body?.hasPrefix("Tombstones never go away here."), true)
    XCTAssertEqual(first.take?.gist, "Tombstones are never compacted, so every sync ships all of them")
    XCTAssertEqual(first.take?.take?.hasPrefix("Valid concern:"), true)
    XCTAssertTrue(r.conversation.filter { $0.waitingOnYou == true }.count < r.conversation.count, "those waiting on you, then the rest")
  }

  func testAReviewFromAnotherDesk() throws {
    let r = try DeskJSON.decoder().decode(
      ReviewRead.self,
      from: Data(#"{"conversation":[{"id":"a","comments":[{"id":"c"},{"nope":1}],"take":null,"side":"sideways"},{"no":"id"}],"conversation_error":"GitHub said no"}"#.utf8))
    XCTAssertEqual(r.conversation.map(\.id), ["a"], "a conversation it can't read is dropped, not the page")
    XCTAssertEqual(r.conversation[0].comments.map(\.id), ["c"])
    XCTAssertNil(r.approve)
    XCTAssertEqual(r.conversationError, "GitHub said no")
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
}
