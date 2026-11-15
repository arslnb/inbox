import XCTest

@testable import Inbox

// What a paired phone writes, against the desk's exact routes (src/server.ts) and the answers the mock gave each
// (web/mock/server.ts), stubbed: the method, the path with the id as one segment, the JSON body and the phone's token.
final class WriteTests: XCTestCase {
  private typealias Answer = StubProtocol.Answer
  private let pr = "acme/api#4127"
  private let head = "000000000000000000000000000009f6a052cc6f"
  private let root = "https://desk.tail1234.ts.net"

  private func client() -> APIClient {
    APIClient(address: DeskAddress(url: URL(string: root)!), token: "inbox_test", session: StubProtocol.session())
  }

  // The one request sent: a POST with the phone's bearer and a JSON body, and no browser's headers.
  private func sent(_ url: String, _ body: [String: Any], line: UInt = #line) throws {
    let all = StubProtocol.requests()
    XCTAssertEqual(all.count, 1, line: line)
    let r = try XCTUnwrap(all.first, line: line)
    XCTAssertEqual(r.httpMethod, "POST", line: line)
    XCTAssertEqual(r.url?.absoluteString, root + url, line: line)
    XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer inbox_test", line: line)
    XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json", line: line)
    XCTAssertNil(r.value(forHTTPHeaderField: "Origin"), line: line)
    let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(r.sentBody, line: line)) as? NSDictionary
    XCTAssertEqual(json, body as NSDictionary, line: line)
  }

  private func refusal<T>(_ path: String, _ status: Int, _ words: String, tag: String = "Conflict", _ run: () async throws -> T) async -> APIError? {
    let body = String(decoding: try! JSONSerialization.data(withJSONObject: ["error": words, "tag": tag]), as: UTF8.self)
    StubProtocol.reset([path: Answer(status: status, body: body)])
    do {
      _ = try await run()
      return nil
    } catch { return error as? APIError }
  }

  func testApprove() async throws {
    let path = "/api/review/acme/api#4127/approve"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"url":"https://github.com/acme/api/pull/4127#pullrequestreview-mock"}"#)])
    let wrote = try await client().approve(pr, head: head)
    XCTAssertEqual(wrote.url, "https://github.com/acme/api/pull/4127#pullrequestreview-mock")
    try sent("/api/review/acme%2Fapi%234127/approve", ["head_oid": head])

    StubProtocol.reset([path: Answer(body: #"{"ok":true,"url":""}"#)])
    _ = try await client().approve(pr, head: head, body: "Looks right.")
    try sent("/api/review/acme%2Fapi%234127/approve", ["head_oid": head, "body": "Looks right."])

    var e = await refusal(path, 409, "can't approve acme/api#4127: it has new commits since you opened it", tag: "Stale") {
      try await self.client().approve(self.pr, head: "old")
    }
    XCTAssertEqual(e, .refused(status: 409, message: "can't approve acme/api#4127: it has new commits since you opened it"))
    e = await refusal(path, 409, "can't approve acme/api#4127: it's your PR") { try await self.client().approve(self.pr, head: self.head) }
    XCTAssertEqual(e?.words, "can't approve acme/api#4127: it's your PR")
    // Paired as a machine (an older pairing): the desk still keeps the write for its window, in these words.
    e = await refusal(path, 403, "approve from the PR's review in the desk", tag: "Forbidden") { try await self.client().approve(self.pr, head: self.head) }
    XCTAssertEqual(e, .refused(status: 403, message: "approve from the PR's review in the desk"))
    e = await refusal(path, 502, "GitHub didn't take the approval: Resource not accessible", tag: "Upstream") {
      try await self.client().approve(self.pr, head: self.head)
    }
    XCTAssertEqual(e, .refused(status: 502, message: "GitHub didn't take the approval: Resource not accessible"))
  }

  func testComment() async throws {
    let path = "/api/review/acme/worker#860/comment"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"url":"https://github.com/acme/worker/issues/860#issuecomment-mock"}"#)])
    let wrote = try await client().comment("acme/worker#860", body: "On it")
    XCTAssertEqual(wrote.url, "https://github.com/acme/worker/issues/860#issuecomment-mock")
    try sent("/api/review/acme%2Fworker%23860/comment", ["body": "On it"])
    let e = await refusal(path, 400, "the comment is empty", tag: "BadRequest") { try await self.client().comment("acme/worker#860", body: "  ") }
    XCTAssertEqual(e, .refused(status: 400, message: "the comment is empty"))
  }

  func testReply() async throws {
    let path = "/api/review/me/notes-app#12/reply"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"url":"https://github.com/me/notes-app/pull/12#discussion-mock"}"#)])
    _ = try await client().reply("me/notes-app#12", to: "PRRT_tomb", body: "Compacting in a follow-up.")
    try sent("/api/review/me%2Fnotes-app%2312/reply", ["id": "PRRT_tomb", "body": "Compacting in a follow-up."])
    let e = await refusal(path, 404, #"no conversation "nope" on me/notes-app#12"#, tag: "NotFound") {
      try await self.client().reply("me/notes-app#12", to: "nope", body: "x")
    }
    XCTAssertEqual(e, .refused(status: 404, message: #"no conversation "nope" on me/notes-app#12"#))
  }

  // A comment on one line: its path, its number on its side, your words and the commit the diff was read at. No range.
  func testACommentOnALine() async throws {
    let path = "/api/review/acme/api#4127/inline"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"url":"https://github.com/acme/api/pull/4127#discussion-mock"}"#)])
    let at = LineSpot(path: "src/planner/plan.ts", line: 17, side: "old", text: "export async function runPlan(q: Query): Promise<PlanResult> {")
    let wrote = try await client().inline(pr, at: at, body: "Why the default?", head: head)
    XCTAssertEqual(wrote.url, "https://github.com/acme/api/pull/4127#discussion-mock")
    try sent(
      "/api/review/acme%2Fapi%234127/inline", ["path": "src/planner/plan.ts", "line": 17, "side": "old", "body": "Why the default?", "head_oid": head])
    let e = await refusal(path, 409, "can't comment on acme/api#4127: it's merged") {
      try await self.client().inline(self.pr, at: at, body: "x", head: self.head)
    }
    XCTAssertEqual(e, .refused(status: 409, message: "can't comment on acme/api#4127: it's merged"))
  }

  func testReadyForReview() async throws {
    let path = "/api/review/acme/web#2303/ready"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"done":false}"#)])
    var r = try await client().ready("acme/web#2303")
    XCTAssertEqual(r.done, false, "ready, and nobody asked: it stays on the desk")
    try sent("/api/review/acme%2Fweb%232303/ready", ["users": [String](), "teams": [String]()])

    StubProtocol.reset([path: Answer(body: #"{"ok":true,"done":true}"#)])
    r = try await client().ready("acme/web#2303", users: ["U_dana"], teams: ["T_core"])
    XCTAssertEqual(r.done, true)
    try sent("/api/review/acme%2Fweb%232303/ready", ["users": ["U_dana"], "teams": ["T_core"]])

    let e = await refusal(path, 409, "acme/web#2303 isn't an open draft") { try await self.client().ready("acme/web#2303") }
    XCTAssertEqual(e, .refused(status: 409, message: "acme/web#2303 isn't an open draft"))
  }

  func testAskReviewers() async throws {
    let path = "/api/review/oss/tinyhttp#205/reviewers"
    StubProtocol.reset([path: Answer(body: #"{"ok":true}"#)])
    try await client().askReviewers("oss/tinyhttp#205", users: ["U_dana"], teams: [])
    try sent("/api/review/oss%2Ftinyhttp%23205/reviewers", ["users": ["U_dana"], "teams": [String]()])
    StubProtocol.reset([path: Answer(body: #"{"ok":true}"#)])
    try await client().askReviewers("oss/tinyhttp#205", users: [], teams: ["T_core"], keep: true)
    try sent("/api/review/oss%2Ftinyhttp%23205/reviewers", ["users": [String](), "teams": ["T_core"], "keep": true])
    let e = await refusal(path, 400, "pick someone to ask", tag: "BadRequest") { try await self.client().askReviewers("oss/tinyhttp#205", users: [], teams: []) }
    XCTAssertEqual(e, .refused(status: 400, message: "pick someone to ask"))
  }

  func testMergeAndTheMoreMenu() async throws {
    StubProtocol.reset(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    _ = try await client().github("acme/worker#875", "merge", head: head)
    try sent("/api/github", ["id": "acme/worker#875", "action": "merge", "head_oid": head])
    for action in ["close", "draft", "reopen", "rerequest", "unrequest"] {
      StubProtocol.reset(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
      _ = try await client().github(pr, action)
      try sent("/api/github", ["id": pr, "action": action])
    }
    StubProtocol.reset(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    _ = try await client().github(pr, "request_changes", head: head, body: "Needs a test")
    try sent("/api/github", ["id": pr, "action": "request_changes", "head_oid": head, "body": "Needs a test"])

    var e = await refusal("/api/github", 409, "can't merge acme/api#4127 now") { try await self.client().github(self.pr, "merge") }
    XCTAssertEqual(e, .refused(status: 409, message: "can't merge acme/api#4127 now"))
    e = await refusal("/api/github", 403, "GitHub actions are yours, from the desk's window", tag: "Forbidden") { try await self.client().github(self.pr, "close") }
    XCTAssertEqual(e?.words, "GitHub actions are yours, from the desk's window")
    e = await refusal("/api/github", 502, "couldn't merge acme/api#4127 on GitHub: Pull Request is not mergeable", tag: "Upstream") {
      try await self.client().github(self.pr, "merge")
    }
    XCTAssertEqual(e?.words, "couldn't merge acme/api#4127 on GitHub: Pull Request is not mergeable")
  }

  // Hand off for merge and Back to desk are /api/act's inflight and takeback.
  func testHandOffAndBackToDesk() async throws {
    let ok = Answer(body: #"{"ok":true,"state":{"id":"acme/billing#2298","inflight_at":"2026-11-13T16:43:34.331Z"},"undo_seq":5}"#)
    StubProtocol.reset(["/api/act": ok])
    _ = try await client().act("acme/billing#2298", "inflight")
    try sent("/api/act", ["id": "acme/billing#2298", "action": "inflight"])
    StubProtocol.reset(["/api/act": ok])
    _ = try await client().act("acme/billing#2298", "takeback")
    try sent("/api/act", ["id": "acme/billing#2298", "action": "takeback"])
    var e = await refusal("/api/act", 409, "acme/ml-pipeline#299 is a draft: mark it ready for review first") {
      try await self.client().act("acme/ml-pipeline#299", "inflight")
    }
    XCTAssertEqual(e, .refused(status: 409, message: "acme/ml-pipeline#299 is a draft: mark it ready for review first"))
    e = await refusal("/api/act", 403, "hand a PR off for merge from the desk's window", tag: "Forbidden") { try await self.client().act(self.pr, "inflight") }
    XCTAssertEqual(e, .refused(status: 403, message: "hand a PR off for merge from the desk's window"))
  }

  func testAnsweringAQuestion() async throws {
    let path = "/api/inquiries/q1c0ffee/answer"
    let inquiry = String(decoding: try Fixture.data("inquiry"), as: UTF8.self)
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"inquiry":\#(inquiry)}"#)])
    let a = try await client().answer("q1c0ffee", text: "Split it")
    XCTAssertEqual(a.inquiry?.id, "q1c0ffee")
    try sent(path, ["text": "Split it"])
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"inquiry":\#(inquiry)}"#)])
    _ = try await client().answer("q1c0ffee", text: nil)
    try sent(path, ["dismiss": true])

    var e = await refusal(path, 409, "already answered") { try await self.client().answer("q1c0ffee", text: "again") }
    XCTAssertEqual(e, .refused(status: 409, message: "already answered"))
    e = await refusal(path, 400, "the answer is empty", tag: "BadRequest") { try await self.client().answer("q1c0ffee", text: "") }
    XCTAssertEqual(e, .refused(status: 400, message: "the answer is empty"))
    e = await refusal(path, 403, "answer it in the desk's window", tag: "Forbidden") { try await self.client().answer("q1c0ffee", text: "x") }
    XCTAssertEqual(e, .refused(status: 403, message: "answer it in the desk's window"))
  }

  func testKickingASession() async throws {
    let id = "session:a83e61d4-0b52-4f7c-8e3a-91c4d6b2f058"
    let path = "/api/sessions/\(id)/kick"
    StubProtocol.reset([path: Answer(body: #"{"ok":true,"args":["--resume","a83e61d4","--bg","Continue where you left off."]}"#)])
    let k = try await client().kick(id)
    XCTAssertNil(k.note, "the mock sends none")
    try sent("/api/sessions/session%3Aa83e61d4-0b52-4f7c-8e3a-91c4d6b2f058/kick", [:])
    let e = await refusal(path, 409, "Migrate the job store to SQLite is rate limited until 09:43; kick it after that") { try await self.client().kick(id) }
    XCTAssertEqual(e, .refused(status: 409, message: "Migrate the job store to SQLite is rate limited until 09:43; kick it after that"))
  }

  // A PR's review: without ahead it's the window's open (the desk may start its AI review), with it a redraw.
  func testTheReviewIsOpenedOrReadAheadAndReviewersBySearch() async throws {
    StubProtocol.reset(["/api/review/me/notes-app#12": Answer(body: String(decoding: try Fixture.data("review-own"), as: UTF8.self))])
    let r = try await client().review("me/notes-app#12", ahead: false)
    XCTAssertEqual(r.conversation.count, 5)
    _ = try await client().review("me/notes-app#12", ahead: true)
    var all = StubProtocol.requests()
    XCTAssertEqual(all.map(\.url?.absoluteString), [root + "/api/review/me%2Fnotes-app%2312", root + "/api/review/me%2Fnotes-app%2312?ahead=1"])
    XCTAssertEqual(all[0].httpMethod, "GET")
    XCTAssertEqual(all[0].value(forHTTPHeaderField: "Authorization"), "Bearer inbox_test")
    let e400 = await refusal("/api/review/acme/worker#860", 400, "acme/worker#860 is an issue") { try await self.client().review("acme/worker#860", ahead: false) }
    XCTAssertEqual(e400, .refused(status: 400, message: "acme/worker#860 is an issue"))

    StubProtocol.reset(["/api/reviewers/acme/web#2303": Answer(body: String(decoding: try Fixture.data("reviewers"), as: UTF8.self))])
    let who = try await client().reviewers("acme/web#2303", search: "da na")
    XCTAssertEqual(who.map(\.login), ["dana", "sam"])
    all = StubProtocol.requests()
    XCTAssertEqual(all.map(\.url?.absoluteString), [root + "/api/reviewers/acme%2Fweb%232303?q=da%20na"])
    let e = await refusal("/api/reviewers/acme/api#4127", 409, "acme/api#4127 isn't your PR") { try await self.client().reviewers(self.pr) }
    XCTAssertEqual(e, .refused(status: 409, message: "acme/api#4127 isn't your PR"))
  }
}

// The store's part of each write: one at a time, the window's words when it lands, the desk's own when it's refused, and a read after.
@MainActor
final class StoreWriteTests: XCTestCase {
  private typealias Answer = StubProtocol.Answer
  private var defaults: UserDefaults!
  private var store: Store!
  private let suite = "dev.inbox.ios.tests.\(UUID().uuidString)"
  private let address = "https://desk.tail1234.ts.net"
  private let head = "000000000000000000000000000009f6a052cc6f"

  private func reads() throws -> [String: Answer] {
    let ok = { (name: String) in Answer(body: String(decoding: try Fixture.data(name), as: UTF8.self)) }
    return ["/api/overview": try ok("overview"), "/api/queue": try ok("queue")]
  }

  // The reads, plus this test's answers.
  private func desk(_ more: [String: Answer]) throws {
    StubProtocol.reset(try reads().merging(more) { $1 })
  }

  private func paths() -> [String] { StubProtocol.requests().map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } }

  private func no(_ status: Int, _ words: String) -> Answer {
    Answer(status: status, body: String(decoding: try! JSONSerialization.data(withJSONObject: ["error": words, "tag": "x"]), as: UTF8.self))
  }

  private func card(_ id: String) throws -> Card { try XCTUnwrap(store.card(id), "no \(id) in the queue fixture") }

  override func setUp() async throws {
    defaults = UserDefaults(suiteName: suite)
    StubProtocol.reset(["/api/pair": Answer(body: #"{"ok":true,"token":"inbox_abc","device":{"id":"0123456789abcdef","name":"iPhone","kind":"phone"}}"#)])
    store = Store(defaults: defaults, session: StubProtocol.session())
    _ = await store.connect(typed: address, code: "ABCD-2345")
    store.stopLive()
    StubProtocol.reset(try reads())
    await store.load()
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suite)
    Keychain.delete(for: address)
  }

  func testApproveSaysSoAndReadsTheDeskAgain() async throws {
    try desk(["/api/review/acme/api#4127/approve": Answer(body: #"{"ok":true,"url":"u"}"#)])
    let took = await store.approve(try card("acme/api#4127"), head: head)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Approved api#4127 on GitHub")
    XCTAssertEqual(store.toast?.undoable, false, "a GitHub write has no undo")
    XCTAssertEqual(paths().first, "POST /api/review/acme/api#4127/approve")
    XCTAssertTrue(paths().contains("GET /api/queue"), "read again")
    XCTAssertEqual(StubProtocol.requests()[0].value(forHTTPHeaderField: "Authorization"), "Bearer inbox_abc", "the token pairing gave")
    XCTAssertFalse(store.busy("acme/api#4127"))
    XCTAssertTrue(store.leaving.isEmpty)
  }

  // A review answer with another head commit: what a push between two reads looks like.
  private func review(_ name: String, head: String) throws -> Answer {
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try Fixture.data(name)) as? [String: Any])
    var item = try XCTUnwrap(json["item"] as? [String: Any])
    item["head_oid"] = head
    json["item"] = item
    return Answer(body: String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self))
  }

  private func sentBody(_ path: String) throws -> [String: String] {
    let req = try XCTUnwrap(StubProtocol.requests().first { $0.httpMethod == "POST" && $0.url?.path == path })
    return try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(req.sentBody))
  }

  // The pin moves with each review that lands (the window since 9f5819a): Approve, Merge and Request changes send the
  // commit the page last drew, not the one it first showed.
  func testApproveSendsTheHeadOfTheLastReviewThatLanded() async throws {
    let id = "acme/api#4127"
    let c = try card(id)
    XCTAssertNil(store.pins[id], "nothing to pin to before its review lands")
    try desk(["/api/review/\(id)": try review("review-steps", head: "a1")])
    _ = await store.readReview(id)
    XCTAssertEqual(store.pins[id], "a1")
    try desk(["/api/review/\(id)": try review("review-steps", head: "b2")])
    _ = await store.readReview(id)
    XCTAssertEqual(store.pins[id], "b2", "a push the page redrew")

    try desk(["/api/review/\(id)/approve": Answer(body: #"{"ok":true,"url":"u"}"#)])
    let took = await store.approve(c)
    XCTAssertTrue(took)
    XCTAssertEqual(try sentBody("/api/review/\(id)/approve"), ["head_oid": "b2"])

    try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    _ = await store.github(c, "request_changes", body: "Needs a test")
    XCTAssertEqual(try sentBody("/api/github"), ["id": id, "action": "request_changes", "head_oid": "b2", "body": "Needs a test"])

    // A push it hasn't drawn yet is the desk's to refuse, in its words.
    let words = "can't approve \(id): it has new commits since you opened it"
    try desk(["/api/review/\(id)/approve": no(409, words)])
    let again = await store.approve(c)
    XCTAssertFalse(again)
    XCTAssertEqual(store.whyNot, words)

    store.closeReview(id)
    XCTAssertNil(store.pins[id], "its page left: the next open pins afresh")
  }

  // The desk says whether you may approve, and why not: the page's Approve is off with its reason.
  func testApproveIsOffWithTheDesksReason() async throws {
    try desk(["/api/review/acme/api#4127": Answer(body: String(decoding: try Fixture.data("review-lean"), as: UTF8.self))])
    guard case .success(let r)? = await store.readReview("acme/api#4127") else { return XCTFail("no review") }
    XCTAssertEqual(r.cantApprove, "Can't approve: you approved this commit.")
    let mine: ReviewView = try Fixture.decode("review-own")
    XCTAssertEqual(mine.cantApprove, "Can't approve: it's your PR.")
    let theirs: ReviewView = try Fixture.decode("review-steps")
    XCTAssertNil(theirs.cantApprove)
    XCTAssertNotNil(try DeskJSON.decoder().decode(ReviewView.self, from: Data("{}".utf8)).cantApprove, "a desk that doesn't say isn't a yes")
  }

  // The desk's own sentence, in a bubble that fades; the row is back, and nothing claims it worked.
  func testARefusalSaysTheDesksWords() async throws {
    let words = "can't approve acme/api#4127: it has new commits since you opened it"
    try desk(["/api/review/acme/api#4127/approve": no(409, words)])
    let took = await store.approve(try card("acme/api#4127"), head: "old")
    XCTAssertFalse(took)
    XCTAssertNil(store.toast)
    XCTAssertEqual(store.notices.map(\.title), [words])
    XCTAssertTrue(store.leaving.isEmpty)
    XCTAssertFalse(store.busy("acme/api#4127"))
    XCTAssertTrue(paths().contains("GET /api/queue"), "what's on screen was old: read again")

    for (status, said) in [(403, "approve from the PR's review in the desk"), (502, "GitHub didn't take the approval: Bad credentials")] {
      try desk(["/api/review/acme/api#4127/approve": no(status, said)])
      let took = await store.approve(try card("acme/api#4127"), head: head)
      XCTAssertFalse(took)
      XCTAssertEqual(store.notices.last?.title, said)
    }
    XCTAssertNotNil(store.address, "a refused write is no revoke")
  }

  func testARevokedPhoneGoesBackToPairing() async throws {
    try desk(["/api/github": no(401, "pair this device first: run desk pair on the desk's machine")])
    let took = await store.github(try card("acme/worker#875"), "merge", head: head)
    XCTAssertFalse(took)
    XCTAssertNil(store.address)
  }

  func testAnUnreachableDeskDuringAWrite() async throws {
    try desk(["/api/review/acme/worker#860/comment": Answer(error: .timedOut)])
    let took = await store.comment(try card("acme/worker#860"), body: "On it")
    XCTAssertFalse(took)
    XCTAssertTrue(store.offline)
    XCTAssertNil(store.toast)
    // No answer isn't a no: the desk may have taken it, so nothing says it wasn't sent, and the desk is read again.
    XCTAssertEqual(store.whyNot, "The desk didn't answer, so it may or may not have been sent. Look before sending it again.")
    for _ in 0..<150 where store.offline { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertFalse(store.offline, "the desk answers its reads: it isn't away")
  }

  // A sheet covers the bubbles, so it says why itself: the desk's own words for a refusal and for a desk still starting.
  func testWhyAWriteWasNotTaken() async throws {
    let c = try card("acme/worker#860")
    try desk(["/api/review/acme/worker#860/comment": no(503, "desk is starting; the first sync can take a minute")])
    var took = await store.comment(c, body: "On it")
    XCTAssertFalse(took)
    XCTAssertEqual(store.whyNot, "desk is starting; the first sync can take a minute")
    try desk(["/api/review/acme/worker#860/comment": no(409, "can't comment on acme/worker#860: it's closed")])
    took = await store.comment(c, body: "On it")
    XCTAssertEqual(store.whyNot, "can't comment on acme/worker#860: it's closed")
    try desk(["/api/review/acme/worker#860/comment": Answer(hangs: true)])
    let first = Task { await self.store.comment(c, body: "On it") }
    for _ in 0..<150 where StubProtocol.requests().isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertNil(store.whyNot, "nothing yet")
    took = await store.comment(c, body: "Again")
    XCTAssertFalse(took)
    XCTAssertEqual(store.whyNot, "Something else is still on its way for it: try again in a moment.")
    first.cancel()
  }

  // While one is on its way, a second press sends nothing; the row has left at once.
  func testNoDoubleSend() async throws {
    try desk(["/api/review/acme/api#4127/approve": Answer(hangs: true)])
    let c = try card("acme/api#4127")
    let first = Task { await self.store.approve(c, head: self.head) }
    for _ in 0..<150 where StubProtocol.requests().isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertTrue(store.busy(c.id))
    XCTAssertTrue(store.leaving.contains(c.id))
    let again = await store.approve(c, head: head)
    XCTAssertFalse(again)
    let other = await store.comment(c, body: "And")
    XCTAssertFalse(other, "nor another write to the same item")
    XCTAssertEqual(paths(), ["POST /api/review/acme/api#4127/approve"])
    first.cancel()
  }

  func testCommentAndReply() async throws {
    try desk(["/api/review/acme/worker#860/comment": Answer(body: #"{"ok":true,"url":"u"}"#)])
    var took = await store.comment(try card("acme/worker#860"), body: "On it")
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Commented on worker#860 on GitHub")

    let review: ReviewView = try Fixture.decode("review-own")
    let convo = try XCTUnwrap(review.conversation.first)
    try desk(["/api/review/me/notes-app#12/reply": Answer(body: #"{"ok":true,"url":"u"}"#)])
    took = await store.reply(try card("me/notes-app#12"), to: convo, body: "Compacting in a follow-up.")
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Sent your reply to azulus")
    let body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[0].sentBody))
    XCTAssertEqual(body, ["id": "PRRT_tomb", "body": "Compacting in a follow-up."])

    try desk(["/api/review/me/notes-app#12/reply": no(400, "the reply is empty")])
    took = await store.reply(try card("me/notes-app#12"), to: convo, body: " ")
    XCTAssertFalse(took, "so the page keeps the draft")
    XCTAssertEqual(store.notices.map(\.title), ["the reply is empty"])
  }

  // A reply stays on its page, waiting on you or not; it leaves only when the desk took the PR off (a reply was all it
  // asked, and this was the last one waiting), which the read after the write says.
  func testAReplyStaysUntilTheDeskTakesItOff() async throws {
    let id = "me/notes-app#12"
    let c = try card(id)
    let review: ReviewView = try Fixture.decode("review-own")
    let quiet = try XCTUnwrap(review.conversation.first { $0.id == "PRRT_name" })
    XCTAssertNotEqual(quiet.waitingOnYou, true)
    let path = "/api/review/\(id)/reply"
    store.path = [.item(id)]

    try desk([path: Answer(body: #"{"ok":true,"url":"u"}"#)])
    var took = await store.reply(c, to: quiet, body: "Renamed, thanks.")
    XCTAssertTrue(took)
    XCTAssertEqual(paths().filter { $0.hasPrefix("POST") }, ["POST \(path)"], "once")
    let body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[0].sentBody))
    XCTAssertEqual(body, ["id": "PRRT_name", "body": "Renamed, thanks."])
    XCTAssertEqual(store.toast?.text, "Sent your reply to kai", "to whoever spoke last there, other than you")
    XCTAssertFalse(store.left(c), "still on the desk: its page stays")
    XCTAssertTrue(store.leaving.isEmpty)

    // Refused: the desk's words for the sheet, which keeps yours.
    try desk([path: no(409, "can't reply on me/notes-app#12: it's merged")])
    took = await store.reply(c, to: quiet, body: "Renamed, thanks.")
    XCTAssertFalse(took, "so the sheet keeps the draft")
    XCTAssertEqual(store.whyNot, "can't reply on me/notes-app#12: it's merged")
    XCTAssertFalse(store.left(c))

    // The last one waiting on a reply-only PR: the desk marks it done, and the read after the write has it so.
    let last = try XCTUnwrap(review.conversation.first { $0.id == "IC_freeze" })
    func marked(_ json: Any) -> Any {
      if let list = json as? [Any] { return list.map(marked) }
      guard var d = json as? [String: Any] else { return json }
      d = d.mapValues(marked)
      if d["id"] as? String == id { d["status"] = "done" }
      return d
    }
    let queue = try JSONSerialization.jsonObject(with: try Fixture.data("queue"))
    let done = String(decoding: try JSONSerialization.data(withJSONObject: marked(queue)), as: UTF8.self)
    try desk([path: Answer(body: #"{"ok":true,"url":"u"}"#), "/api/queue": Answer(body: done)])
    took = await store.reply(c, to: last, body: "Yes, before the freeze.")
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Sent your reply to priya")
    XCTAssertTrue(store.left(c), "off the desk: back to the list")
    XCTAssertNil(store.toast?.undo, "a reply has nothing to undo")
  }

  // A comment on a line is part of reviewing, not its end: sent once, at the commit the diff is at, and the PR and its page stay.
  func testACommentOnALineStaysOnThePage() async throws {
    let id = "acme/api#4127"
    let c = try card(id)
    let review: ReviewView = try Fixture.decode("review-steps")
    let diffHead = try XCTUnwrap(review.diffHead)
    let at = LineSpot(path: "src/planner/plan.ts", line: 23, side: "new")
    let path = "/api/review/\(id)/inline"
    store.path = [.item(id)]

    try desk([path: Answer(body: #"{"ok":true,"url":"u"}"#)])
    var took = await store.inline(c, at: at, body: "Say how many it dropped.", head: diffHead)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Commented on plan.ts:23 on GitHub")
    XCTAssertEqual(paths().filter { $0.hasPrefix("POST") }, ["POST \(path)"], "once")
    let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.requests()[0].sentBody)) as? NSDictionary
    XCTAssertEqual(
      body, ["path": "src/planner/plan.ts", "line": 23, "side": "new", "body": "Say how many it dropped.", "head_oid": diffHead] as NSDictionary,
      "exactly these, pinned to the diff's commit")
    XCTAssertEqual(store.path, [.item(id)], "the page isn't left")
    XCTAssertNotNil(store.card(id), "and the PR stays on the desk")
    XCTAssertTrue(store.leaving.isEmpty)

    // Refused: the desk's words for the sheet, which keeps yours.
    try desk([path: no(409, "can't comment on acme/api#4127: it's merged")])
    took = await store.inline(c, at: at, body: "Say how many it dropped.", head: diffHead)
    XCTAssertFalse(took, "so the sheet keeps the draft")
    XCTAssertEqual(store.whyNot, "can't comment on acme/api#4127: it's merged")
    XCTAssertEqual(store.path, [.item(id)])

    // A second press while it's on its way sends nothing; another line's goes, and so does Approve.
    try desk([path: Answer(hangs: true), "/api/review/\(id)/approve": Answer(body: #"{"ok":true,"url":"u"}"#)])
    let first = Task { await self.store.inline(c, at: at, body: "One", head: diffHead) }
    for _ in 0..<150 where StubProtocol.requests().isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    took = await store.inline(c, at: at, body: "Two", head: diffHead)
    XCTAssertFalse(took)
    XCTAssertEqual(store.whyNot, "Still sending your last comment there.")
    XCTAssertEqual(paths(), ["POST \(path)"])
    XCTAssertFalse(store.busy(id), "the PR itself isn't held: Approve stays")
    XCTAssertFalse(store.leaving.contains(id))
    first.cancel()
  }

  func testReadyForReviewAndAskingReviewers() async throws {
    let draft = try card("acme/web#2303")
    let dana = Reviewer(id: "U_dana", login: "dana", name: "Dana Okafor", team: false, suggested: true)
    let core = Reviewer(id: "T_core", login: "acme/core", name: "Core", team: true, suggested: false)
    let ready = "/api/review/acme/web#2303/ready"

    try desk([ready: Answer(body: #"{"ok":true,"done":false}"#)])
    var took = await store.ready(draft)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Marked web#2303 ready for review on GitHub. Nobody's asked to review it yet")

    try desk([ready: Answer(body: #"{"ok":true,"done":true}"#)])
    took = await store.ready(draft, asking: [dana, core])
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Marked web#2303 ready for review and asked dana, acme/core on GitHub")
    var sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.requests()[0].sentBody)) as? NSDictionary
    XCTAssertEqual(sent, ["users": ["U_dana"], "teams": ["T_core"]], "people and teams apart, by node id")

    // Half done: it is ready, the requests weren't sent. The window's words say what's left to do.
    try desk([ready: no(502, "Marked it ready, but GitHub didn't ask for the reviews: Could not resolve to a node")])
    took = await store.ready(draft, asking: [dana])
    XCTAssertFalse(took)
    XCTAssertEqual(store.notices.map(\.title), ["Marked it ready, but GitHub didn't ask for the reviews: Could not resolve to a node. Ask dana on GitHub."])

    // The More menu's "ready" is the same write.
    try desk([ready: Answer(body: #"{"ok":true,"done":false}"#)])
    took = await store.github(draft, "ready")
    XCTAssertTrue(took)
    XCTAssertEqual(paths().first, "POST \(ready)")

    let mine = try card("oss/tinyhttp#205")
    try desk(["/api/review/oss/tinyhttp#205/reviewers": Answer(body: #"{"ok":true}"#)])
    took = await store.askReviewers(mine, [dana], keep: true)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Asked dana to review tinyhttp#205 on GitHub")
    sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.requests()[0].sentBody)) as? NSDictionary
    XCTAssertEqual(sent, ["users": ["U_dana"], "teams": [String](), "keep": true])
  }

  func testMergeAndTheMoreMenusWords() async throws {
    let mine = try card("acme/worker#875")
    let said = [
      "merge": "Merged on GitHub: worker#875", "reopen": "Reopened on GitHub: worker#875", "rerequest": "Asked them to review it again on GitHub: worker#875",
      "unrequest": "Took you off its reviewers on GitHub: worker#875", "request_changes": "Requested changes on GitHub: worker#875",
    ]
    for (action, words) in said {
      try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
      let took = await store.github(mine, action, head: head, body: action == "request_changes" ? "Needs a test" : nil)
      XCTAssertTrue(took)
      XCTAssertEqual(store.toast?.text, words)
      XCTAssertEqual(store.toast?.undoable, false)
    }
    try desk(["/api/github": no(409, "can't merge acme/worker#875 now")])
    let took = await store.github(mine, "merge", head: head)
    XCTAssertFalse(took)
    XCTAssertEqual(store.notices.map(\.title), ["can't merge acme/worker#875 now"])
    XCTAssertEqual(Set(Words.more.keys).subtracting(Words.did.keys), ["ready"], "every write the menu names says what it did; ready has its own words")
  }

  // The toast's Undo for the two writes the window undoes: a closed PR is reopened, a converted draft made ready again.
  func testUndoOfACloseAndOfADraft() async throws {
    let mine = try card("acme/worker#875")
    try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    await store.github(mine, "close")
    XCTAssertEqual(store.toast?.text, "Closed on GitHub: worker#875")
    XCTAssertEqual(store.toast?.revert, Toast.Revert(id: "acme/worker#875", to: "reopen"))
    try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    store.undo()
    for _ in 0..<150 where store.toast == nil || store.busy(mine.id) { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertEqual(store.toast?.text, "Undid it on GitHub: worker#875 is open again")
    var body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[0].sentBody))
    XCTAssertEqual(body, ["id": "acme/worker#875", "action": "reopen"])

    try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    await store.github(mine, "draft")
    XCTAssertEqual(store.toast?.text, "Converted to a draft on GitHub: worker#875")
    XCTAssertEqual(store.toast?.revert?.to, "ready")
    // Ready for review took it off the desk (done), so that is undone too.
    try desk([
      "/api/review/acme/worker#875/ready": Answer(body: #"{"ok":true,"done":true}"#), "/api/act": Answer(body: #"{"ok":true,"state":{},"undo_seq":0}"#),
    ])
    store.undo()
    for _ in 0..<150 where store.toast == nil || store.busy(mine.id) { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertEqual(store.toast?.text, "Undid it on GitHub: worker#875 is ready for review again")
    XCTAssertEqual(Array(paths().prefix(2)), ["POST /api/review/acme/worker#875/ready", "POST /api/act"])
    body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[1].sentBody))
    XCTAssertEqual(body, ["id": "acme/worker#875", "action": "undo"])

    // An issue's close has no undo here, as in the window.
    try desk(["/api/github": Answer(body: #"{"ok":true,"url":""}"#)])
    await store.github(try card("acme/worker#860"), "close")
    XCTAssertEqual(store.toast?.undoable, false)
  }

  func testHandOffAndBackToDesk() async throws {
    let mine = try card("acme/worker#875")
    try desk(["/api/act": Answer(body: #"{"ok":true,"state":{},"undo_seq":5}"#)])
    var took = await store.handOff(mine)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Handed off for merge: worker#875. Your agent gets it merged.")
    XCTAssertEqual(store.toast?.undoable, false, "Back to desk is the undo")
    var body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[0].sentBody))
    XCTAssertEqual(body, ["id": "acme/worker#875", "action": "inflight"])

    try desk(["/api/act": Answer(body: #"{"ok":true,"state":{},"undo_seq":6}"#)])
    took = await store.backToDesk(mine)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Back on your desk: worker#875")
    body = try JSONDecoder().decode([String: String].self, from: try XCTUnwrap(StubProtocol.requests()[0].sentBody))
    XCTAssertEqual(body, ["id": "acme/worker#875", "action": "takeback"])

    try desk(["/api/act": no(409, "nobody's asked to review acme/worker#875: add reviewers first")])
    took = await store.handOff(mine)
    XCTAssertFalse(took)
    XCTAssertEqual(store.notices.map(\.title), ["nobody's asked to review acme/worker#875: add reviewers first"])
  }

  func testAnsweringAndDismissingAQuestion() async throws {
    let asked = try XCTUnwrap(store.queue?.inquiries)
    let own = try XCTUnwrap(asked.first { $0.id == "q1c0ffee" })  // the coordinator's
    let other = try XCTUnwrap(asked.first { $0.id == "q2bead00" })
    let count = store.inboxCount
    let inquiry = String(decoding: try Fixture.data("inquiry"), as: UTF8.self)

    try desk(["/api/inquiries/q1c0ffee/answer": Answer(hangs: true)])
    let waiting = Task { await self.store.answer(own, text: "Split it") }
    for _ in 0..<150 where StubProtocol.requests().isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertEqual(store.inboxCount, count - 1, "its row leaves at once")
    waiting.cancel()

    try desk(["/api/inquiries/q2bead00/answer": Answer(body: #"{"ok":true,"inquiry":\#(inquiry)}"#)])
    var took = await store.answer(other, text: "The core first")
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Answered sentry: ViewerContext rollout")
    took = await store.answer(other, text: nil)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Dismissed sentry: ViewerContext rollout's question")
    XCTAssertEqual(Words.fromName(own.from, start: false), "your agent", "Answered your agent")

    try desk(["/api/inquiries/q2bead00/answer": no(409, "already answered")])
    took = await store.answer(other, text: "again")
    XCTAssertFalse(took)
    XCTAssertEqual(store.notices.map(\.title), ["already answered"])
    XCTAssertEqual(store.inboxCount, count, "and its row is back")
  }

  func testKickingASession() async throws {
    let s = try XCTUnwrap(store.queue?.sessions.first { $0.actions == ["kick"] })
    let path = "/api/sessions/\(s.id)/kick"
    try desk([path: Answer(body: #"{"ok":true,"args":["--resume","x","--bg","Continue where you left off."],"note":null}"#)])
    var took = await store.kick(s)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Kicked Migrate the job store to SQLite: it carries on in the background.")
    XCTAssertEqual(paths().first, "POST \(path)")

    var resumes = s
    resumes.actions = ["resume", "attach"]
    took = await store.kick(resumes)
    XCTAssertTrue(took)
    XCTAssertEqual(store.toast?.text, "Resumed Migrate the job store to SQLite: it carries on in the background.")

    try desk([path: no(409, "Migrate the job store to SQLite is rate limited until 09:43; kick it after that")])
    took = await store.kick(s)
    XCTAssertFalse(took)
    XCTAssertEqual(store.notices.map(\.title), ["Migrate the job store to SQLite is rate limited until 09:43; kick it after that"])
  }

  func testTheReadsForReplyAndReviewers() async throws {
    try desk([
      "/api/review/me/notes-app#12": Answer(body: String(decoding: try Fixture.data("review-own"), as: UTF8.self)),
      "/api/reviewers/acme/web#2303": Answer(body: String(decoding: try Fixture.data("reviewers"), as: UTF8.self)),
      "/api/review/acme/worker#860": no(400, "acme/worker#860 is an issue; reviews are for pull requests"),
    ])
    guard case .success(let review) = await store.readReview("me/notes-app#12") else { return XCTFail("no review") }
    XCTAssertEqual(review.conversation.filter { $0.waitingOnYou == true }.first?.id, "PRRT_tomb")
    XCTAssertNil(StubProtocol.requests().first?.url?.query, "its page's open")
    guard case .success(let who) = await store.fetchReviewers("acme/web#2303") else { return XCTFail("no reviewers") }
    XCTAssertEqual(who.map(\.login), ["dana", "sam"])
    guard case .failure(let e) = await store.readReview("acme/worker#860") else { return XCTFail("an issue has no review") }
    XCTAssertEqual(e.words, "acme/worker#860 is an issue; reviews are for pull requests")
    XCTAssertTrue(store.notices.isEmpty, "the page says a failed read; no bubble")
  }
}
