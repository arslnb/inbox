import XCTest

@testable import Inbox

// The window's own words, against the cases web/test/view.test.ts and notices.test.ts hold web/src/format.ts to.
final class FormatTests: XCTestCase {
  private let now = Words.date("2026-10-27T12:00:00Z")!
  private func back(_ hours: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-hours * 3600)) }

  private func card(_ json: String = "") throws -> Card {
    let base = #"{"id":"a/b#1","kind":"pr","repo":"getsentry/seer","number":9085,"title":"t""#
    return try DeskJSON.decoder().decode(Card.self, from: Data("\(base)\(json.isEmpty ? "" : ",")\(json)}".utf8))
  }

  func testAge() {
    XCTAssertEqual(Words.age("2026-10-27T11:20:00Z", now: now), "40m")
    XCTAssertEqual(Words.age("2026-10-27T07:00:00Z", now: now), "5h")
    XCTAssertEqual(Words.age("2026-10-24T12:00:00Z", now: now), "3d")
    // Rounded before the switch to days: 47.6h and 48.3h both read "2d".
    XCTAssertEqual(Words.age(back(47.6), now: now), "2d")
    XCTAssertEqual(Words.age(back(48.3), now: now), "2d")
    XCTAssertEqual(Words.age(back(47.4), now: now), "47h")
    XCTAssertEqual(Words.age("2026-10-27T12:00:05Z", now: now), "0m", "a time ahead of this phone's clock reads 0m, not a negative age")
    XCTAssertEqual(Words.age("2026-10-27T11:00:20Z", now: now), "1h")
    XCTAssertEqual(Words.age("2026-10-27T11:00:40.000Z", now: now), "59m")
    XCTAssertEqual(Words.age(nil, now: now), "")
  }

  // web/test/view.test.ts: "checks: shards of one check are one row with its worst dot, what's wrong first; one alone keeps its whole name".
  func testCheckGroups() {
    let c = { (name: String, state: String, optional: Bool) in Checks.Check(name: name, state: state, optional: optional, url: "") }
    let groups = CheckGroup.of([
      c("backend test (0)", "passing", false),
      c("backend test (1)", "running", false),
      c("backend test (2)", "passing", false),
      c("lint", "passing", false),
      c("acceptance [1/2]", "failing", false),
      c("acceptance [2/2]", "skipped", false),
      c("codecov", "failing", true),
      c("docs", "skipped", false),
    ])
    XCTAssertEqual(groups.map(\.name), ["acceptance", "codecov", "backend test", "lint", "docs"])
    XCTAssertEqual(groups.map(\.dot), [.red, .amber, .yellow, .green, .grey])
    XCTAssertEqual(groups.map(\.checks.count), [2, 1, 3, 1, 1])
    XCTAssertEqual(CheckDot(c("x", "cancelled", false)), .red)
    XCTAssertEqual(groups.map(\.dot.words), ["failing", "failing, not required", "running", "passing", "skipped"])

    // The other marks a shard goes by, one alone keeping its whole name, and a name that is only a mark.
    let names = { (list: [String]) in CheckGroup.of(list.map { c($0, "passing", false) }).map(\.name) }
    XCTAssertEqual(names(["e2e #1", "e2e #2", "unit 1", "unit 2", "it shard 1 of 5", "it Shard 2 of 5", "db 1/2", "db 2/2"]), ["e2e", "unit", "it", "db"])
    XCTAssertEqual(names(["e2e (chromium)", "e2e (firefox)", "lint"]), ["e2e", "lint"])
    XCTAssertEqual(names(["unit tests (1/3)"]), ["unit tests (1/3)"])
    XCTAssertEqual(names(["(1)", "42"]), ["(1)", "42"])
    XCTAssertEqual(names(["b", "a"]), ["b", "a"], "as the desk listed them within a dot")
    XCTAssertTrue(CheckGroup.of([]).isEmpty)
  }

  // The mock's eleven checks are seven rows: past six, the passing and skipped wait behind one line.
  func testAFixturesChecksFold() throws {
    let r: ReviewView = try Fixture.decode("review")
    let groups = CheckGroup.of(try XCTUnwrap(r.checks).list)
    XCTAssertEqual(groups.map(\.name), ["build", "codecov/patch", "e2e", "lint", "typecheck", "unit tests", "visual diff", "deploy preview"])
    XCTAssertEqual(groups.first { $0.name == "unit tests" }?.checks.count, 3)
    XCTAssertTrue(groups.count > CheckGroup.rows)
    XCTAssertTrue(groups.allSatisfy(\.dot.quiet), "all passing or skipped: opened, it shows its one line until Show more")
  }

  func testAgoAndSince() {
    XCTAssertEqual(Words.ago(back(47.6), now: now), "2d ago")
    XCTAssertEqual(Words.ago("2026-10-27T11:59:20Z", now: now), "40s ago")
    XCTAssertEqual(Words.ago("2026-10-27T12:00:05Z", now: now), "0s ago")
    XCTAssertEqual(Words.ago("2026-10-27T11:55:00Z", now: now), "5m ago")
    XCTAssertEqual(Words.sinceText("2026-10-27T11:59:30Z", now: now), "just now")
    XCTAssertEqual(Words.sinceText("2026-10-27T11:20:00Z", now: now), "40m")
  }

  func testWhen() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    utc.locale = Locale(identifier: "en_US")
    XCTAssertEqual(Words.when("2026-10-27T14:30:00Z", now: now, calendar: utc), "14:30")
    XCTAssertEqual(Words.when("2026-10-27T09:05:00.000Z", now: now, calendar: utc), "9:05")
    XCTAssertEqual(Words.when("2026-10-31T09:00:00Z", now: now, calendar: utc), "Sat 9:00")
    XCTAssertEqual(Words.when("2026-11-12T09:00:00Z", now: now, calendar: utc), "Nov 12 9:00")
  }

  func testRefsAndNames() throws {
    XCTAssertEqual(try card().shortRef, "seer#9085")
    XCTAssertEqual(Words.fromName("Inbox coordinator"), "Your agent")
    XCTAssertEqual(Words.fromName("Inbox coordinator", start: false), "your agent")
    XCTAssertEqual(Words.fromName("Review Desk coordinator"), "Your agent", "its name before the rename to Inbox")
    XCTAssertEqual(Words.fromName("sentry: rollout"), "sentry: rollout")
    XCTAssertEqual(Words.capitalized("asked by name"), "Asked by name")
    XCTAssertEqual(Words.plural(1, "comment"), "1 comment")
    XCTAssertEqual(Words.plural(4, "comment"), "4 comments")
  }

  func testClearedText() throws {
    XCTAssertEqual(Words.clearedText(try card(#""status":"snoozed","snooze_until":null"#)), "snoozed until activity")
    XCTAssertEqual(Words.clearedText(try card(#""status":"muted""#)), "muted")
    XCTAssertEqual(Words.clearedText(try card(#""status":"done""#)), "done until someone else acts")
    XCTAssertEqual(Words.clearedText(try card(#""status":"snoozed","snooze_when":"ci""#)), "snoozed until CI passes")
    XCTAssertEqual(Words.clearedText(try card(#""status":"active""#)), "")
    let timed = Words.clearedText(try card(#""status":"snoozed","snooze_until":"2026-10-31T09:00:00Z""#), now: now)
    XCTAssertTrue(timed.hasPrefix("snoozed until ") && timed.hasSuffix(":00 or new activity"), timed)
  }

  // The times, Until activity, then what the item can wait on, in the desk's order.
  func testSnoozeOptions() throws {
    let options = SnoozeOption.all(try card(#""wake_on":["ci","push"]"#))
    XCTAssertEqual(
      options.map(\.label),
      ["1 hour", "3 hours", "Tomorrow 9:00", "Monday 9:00", "Until activity", "Until CI passes", "Until new commits"])
    XCTAssertEqual(options.map(\.until), ["1h", "3h", "tomorrow", "monday", "activity", "ci", "push"])
    XCTAssertEqual(options[0].toast, "for an hour (or until new activity)")
    XCTAssertEqual(options[5].toast, "until CI passes")
    XCTAssertEqual(SnoozeOption.all(try card()).count, 5)
  }

  func testEventText() throws {
    let event = { (json: String) in try DeskJSON.decoder().decode(ActivityEvent.self, from: Data(json.utf8)) }
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"reviewed","actor":"alice","data":{"state":"approved"}}"#), me: "me"), "alice approved")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"reviewed","actor":"Me","data":{"state":"changes_requested"}}"#), me: "me"), "you requested changes")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"ci","actor":"","data":{"from":"green","to":"red"}}"#), me: "me"), "CI went red")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"pushed","actor":"","data":{}}"#), me: "me"), "new commits")
    XCTAssertEqual(
      Words.eventText(try event(#"{"kind":"review_requested","actor":"priya","data":{"reviewer":"backend","type":"team","codeowner":true}}"#), me: "me"),
      "priya asked @backend")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"review_requested","actor":"priya","data":{"reviewer":"me","type":"user"}}"#), me: "me"), "priya asked you")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"conflict","actor":"","data":{"base":"main"}}"#), me: "me"), "conflicts with main")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"unblocked","actor":"","data":{"was":"x","merged":"api#12"}}"#), me: "me"), "unblocked: api#12 merged")
    XCTAssertEqual(Words.eventText(try event(#"{"kind":"teleported","actor":"x"}"#), me: "me"), "teleported", "an event this app doesn't know reads as its kind")
  }

  // An item's recent activity leaves out what its why already says, in its words or in others for the same thing.
  func testAWhySaysAFact() {
    XCTAssertTrue(Words.says("Assigned to you", "assigned to you"))
    XCTAssertTrue(Words.says("red CI on your PR", "CI went red"))
    XCTAssertTrue(Words.says("conflicts with main", "merge conflict"))
    XCTAssertTrue(Words.says("you requested changes", "dana requested changes"))
    XCTAssertTrue(Words.says("2 approvals", "alice approved"))
    XCTAssertFalse(Words.says("assigned to you", "nina commented"))
    XCTAssertFalse(Words.says("", "nina commented"))
    XCTAssertFalse(Words.says("asked you directly", "CI went red"))
    XCTAssertFalse(Words.says("a credible plan", "CI went red"), "red inside a word isn't red")
  }

  func testTheInboxCountsWhatNeedsYou() throws {
    let q: QueueView = try Fixture.decode("queue")
    // Urgent and Standard, the questions and the sessions; FYI and notes aren't counted.
    XCTAssertEqual(Lists.inboxCount(q), 12 + 13 + 2 + 2)
    XCTAssertEqual(Lists.inboxCount(q, leaving: ["acme/api#4127", "session:5f1c2a90-7d3e-4b8a-9c11-2e6f0a4b7d21"]), 27)
  }

  // The one list the client sorts: what you finished and what resolved, newest first.
  // web/test/view.test.ts: "the filter's people: author: and involves: as pills once a space follows, matched as you type them".
  func testTheFiltersPeople() throws {
    let parsed = Filter.parse("author:dana fix involves:@pri")
    XCTAssertEqual(parsed.terms, [Filter.Term(key: "author", who: "dana", done: true), Filter.Term(key: "involves", who: "pri", done: false)])
    XCTAssertEqual(parsed.text, "fix")
    XCTAssertEqual(Filter.rest("author:dana fix involves:pri"), "fix involves:pri")
    XCTAssertEqual(Filter.rest("Author:dana "), "")
    XCTAssertEqual(Filter.of([Filter.Term(key: "author", who: "dana")], "fix "), "author:dana fix ")
    XCTAssertEqual(Filter.parse("AUTHOR:Dana ").terms, [Filter.Term(key: "author", who: "Dana", done: true)], "the key in any case")
    XCTAssertEqual(Filter.parse("label:bug http://x").text, "label:bug http://x", "any other word with a colon is text")
    XCTAssertEqual(Filter.rest("  fix  the bug "), "fix  the bug ", "as typed")

    let card = { (id: String, more: String) in
      let repo = String(id.split(separator: "#")[0])
      let json = #"{"id":"\#(id)","kind":"pr","repo":"\#(repo)","number":\#(id.split(separator: "#")[1]),"title":"A PR"\#(more)}"#
      return try DeskJSON.decoder().decode(Card.self, from: Data(json.utf8))
    }
    let rows = [
      try card("acme/api#1", #","author":"dana","by":"dana","people":["dana","priya"]"#),
      try card("acme/api#7", #","author":"renovate[bot]","author_bot":true,"by":"priya","people":["priya","marco"]"#),
      try card("acme/web#8", #","author":"me","by":"you","people":["me","dana"]"#),
    ]
    let ids = { (f: String) in rows.filter { Filter.matches($0, f, me: "me") }.map(\.id) }
    XCTAssertEqual(ids("author:dana "), ["acme/api#1"])
    XCTAssertEqual(ids("author:pri"), ["acme/api#7"], "a bot's PR is by whom it was opened for")
    XCTAssertEqual(ids("involves:dana "), ["acme/api#1", "acme/web#8"])
    XCTAssertEqual(ids("involves:marco api#7"), ["acme/api#7"], "with words too")
    XCTAssertEqual(ids("author:you "), ["acme/web#8"])
    XCTAssertEqual(ids("author:me"), ["acme/web#8"])
    XCTAssertEqual(ids("involves:you "), ["acme/web#8"])
    XCTAssertEqual(ids("involves:"), ["acme/api#1", "acme/api#7", "acme/web#8"], "a key with no one yet filters nothing")
    XCTAssertEqual(ids("author:@DANA"), ["acme/api#1"], "a leading @ dropped, any case")
    XCTAssertEqual(ids("WEB"), ["acme/web#8"], "the repo")
    XCTAssertEqual(ids("renovate"), ["acme/api#7"], "the author")
    XCTAssertEqual(ids("api#7"), ["acme/api#7"], "the short ref")
    XCTAssertEqual(ids("a pr"), ["acme/api#1", "acme/api#7", "acme/web#8"], "the title")
    XCTAssertEqual(ids("   "), ["acme/api#1", "acme/api#7", "acme/web#8"])
    XCTAssertEqual(ids("nothing"), [])
    // With no people listed, its author is who's on it.
    let bare = try card("acme/api#9", #","author":"kai","by":"kai""#)
    XCTAssertTrue(Filter.matches(bare, "involves:kai", me: "me"))
    XCTAssertFalse(Filter.matches(bare, "involves:dana", me: "me"))

    XCTAssertEqual(
      Filter.people(rows, me: "me"),
      [
        Filter.Person(login: "dana", author: true), Filter.Person(login: "priya", author: true), Filter.Person(login: "marco", author: false),
        Filter.Person(login: "me", author: true),
      ])

    let note = try DeskJSON.decoder().decode(Note.self, from: Data(#"{"id":"n1","text":"Ask Priya about the planner"}"#.utf8))
    XCTAssertTrue(Filter.matches(note, " PRIYA "))
    XCTAssertTrue(Filter.matches(note, ""))
    XCTAssertFalse(Filter.matches(note, "author:priya "), "a note has only its words")
  }

  // Filter.tsx's suggest(), pick() and drop().
  func testWhatTheFilterSuggests() {
    let people = ["dana", "priya", "marco", "me", "daniel", "dan-b", "danielle"].map { Filter.Person(login: $0, author: $0 != "marco" && $0 != "danielle") }
    let pick = { (key: String, login: String) in Filter.Pick(key: key, login: login) }
    XCTAssertEqual(Filter.suggest("", people), [pick("author", ""), pick("involves", "")], "an empty box: the two keys")
    XCTAssertEqual(Filter.suggest("pri", people), [pick("author", "priya"), pick("involves", "priya")])
    XCTAssertEqual(Filter.suggest("@MAR", people), [pick("involves", "marco")], "someone who wrote none is only involved")
    XCTAssertEqual(
      Filter.suggest("dan", people).map(\.id),
      ["author:dana", "author:daniel", "author:dan-b", "involves:dana", "involves:daniel", "involves:dan-b", "involves:danielle"], "four people at most")
    XCTAssertEqual(Filter.suggest("author:", people).map(\.login), ["dana", "priya", "me", "daniel", "dan-b"], "who wrote a row")
    XCTAssertEqual(Filter.suggest("involves:", people).count, 7)
    XCTAssertEqual(Filter.suggest("Involves:@da", people).map(\.login), ["dana", "daniel", "dan-b", "danielle"])
    let many = (1...12).map { Filter.Person(login: "p\($0)", author: true) }
    XCTAssertEqual(Filter.suggest("author:", many).count, 8)

    XCTAssertEqual(Filter.offered("", people).count, 2)
    XCTAssertEqual(Filter.offered("author:dana ", people).count, 2, "after a pill, the keys again")
    XCTAssertEqual(Filter.offered("fix ", people), [], "words typed and none being typed: nothing")
    XCTAssertEqual(Filter.offered("fix pri", people).map(\.id), ["author:priya", "involves:priya"])
    XCTAssertEqual(Filter.offered("zzz", people), [])

    XCTAssertEqual(Filter.picked(pick("author", ""), in: ""), "author:")
    XCTAssertEqual(Filter.picked(pick("author", "dana"), in: "author:"), "author:dana ")
    XCTAssertEqual(Filter.picked(pick("involves", "priya"), in: "author:dana fix pri"), "author:dana involves:priya fix ")
    XCTAssertEqual(Filter.picked(pick("involves", ""), in: "author:dana fix "), "author:dana fix involves:")
    XCTAssertEqual(Filter.dropped(from: "author:dana involves:priya fix"), "author:dana fix")
    XCTAssertEqual(Filter.dropped(0, from: "author:dana involves:priya fix"), "involves:priya fix")
    XCTAssertEqual(Filter.dropped(from: "fix"), "fix", "no pill to take off")
    XCTAssertEqual(Filter.word("fix pri"), "pri")
    XCTAssertEqual(Filter.word("fix "), "")
  }

  // Avatar.tsx: a person's picture is asked of GitHub by their login alone; none for you or a bot that wrote its own PR.
  @MainActor
  func testWhosePictureARowShows() throws {
    XCTAssertEqual(Avatar.url("dana")?.absoluteString, "https://avatars.githubusercontent.com/dana?s=40")
    XCTAssertEqual(Avatar.url("@ana-k")?.absoluteString, "https://avatars.githubusercontent.com/ana-k?s=40")
    XCTAssertEqual(Avatar.url("acme-junior[bot]")?.absoluteString, "https://avatars.githubusercontent.com/acme-junior%5Bbot%5D?s=40")
    XCTAssertNil(Avatar.url(""))
    XCTAssertNil(Avatar.url("you/../x"))
    XCTAssertNil(Avatar.url("a b"))
    XCTAssertNil(Avatar.url("acme/reviewers"), "a team has none")
    let card = { (more: String) in
      try DeskJSON.decoder().decode(Card.self, from: Data(#"{"id":"a/b#1","kind":"pr","repo":"a/b","number":1,"title":"t"\#(more)}"#.utf8))
    }
    XCTAssertEqual(try card(#","author":"dana","by":"dana""#).face, "dana")
    XCTAssertNil(try card(#","author":"me","by":"you""#).face, "none for you")
    XCTAssertNil(try card(#","author":"dependabot[bot]","author_bot":true,"by":"dependabot[bot]""#).face, "a bot's own PR")
    XCTAssertEqual(try card(#","author":"acme-junior[bot]","author_bot":true,"by":"dana""#).face, "dana", "a bot's PR opened for dana")
    XCTAssertNil(try card(#","author":"acme-junior[bot]","author_bot":true,"by":"you""#).face)
    let standing = { (who: String) in try DeskJSON.decoder().decode(Standings.Standing.self, from: Data(#"{"who":"\#(who)","state":"asked"}"#.utf8)).face }
    XCTAssertEqual(try standing("marco"), "marco")
    XCTAssertNil(try standing("you"))
    XCTAssertNil(try standing("@ml-team"), "a team has none")
  }

  // Note.tsx's WHEN, and what goes to /api/notes as `remind`.
  func testANotesReminder() throws {
    XCTAssertEqual(Remind.choices.map(\.label), ["No reminder", "In 1 hour", "In 3 hours", "Tomorrow 9:00", "Monday 9:00", "Pick a time…"])
    let at = try XCTUnwrap(Words.date("2026-11-16T09:30:00.000Z"))
    for pick in ["", "1h", "3h", "tomorrow", "monday"] { XCTAssertEqual(Remind.value(pick, at: at), pick) }
    XCTAssertEqual(Remind.value("pick", at: at), "2026-11-16T09:30:00.000Z", "as JavaScript's toISOString()")
    // Left where it was, it goes back as the desk sent it; moved, as the new time.
    let note = try DeskJSON.decoder().decode(Note.self, from: Data(#"{"id":"n1","text":"t","remind_at":"2026-11-16T09:30:00Z"}"#.utf8))
    XCTAssertEqual(Remind.value("pick", at: at, was: note), "2026-11-16T09:30:00Z")
    XCTAssertEqual(Remind.value("pick", at: at.addingTimeInterval(60), was: note), "2026-11-16T09:31:00.000Z")
    XCTAssertEqual(Remind.value("", at: at, was: note), "", "No reminder takes it off")
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    XCTAssertEqual(Remind.nextHour(try XCTUnwrap(Words.date("2026-11-16T09:30:10.000Z")), calendar: utc), Words.date("2026-11-16T10:00:00.000Z"))
  }

  // format.ts's issueUrl(): what a question is about, when the desk doesn't hold its card. Nothing for what isn't an id.
  func testAnItemOnGitHubByItsId() {
    XCTAssertEqual(Words.issueURL("acme/api#4127")?.absoluteString, "https://github.com/acme/api/issues/4127")
    XCTAssertEqual(Words.issueURL("me/notes-app.v2#12")?.absoluteString, "https://github.com/me/notes-app.v2/issues/12")
    XCTAssertNil(Words.issueURL("acme/api"))
    XCTAssertNil(Words.issueURL("acme/api#x"))
    XCTAssertNil(Words.issueURL("evil.example/a/b#1"))
    XCTAssertNil(Words.issueURL("a b/c#1"))
  }

  // web/test/view.test.ts: "treeGuides draws Blocked's tree from its depths: a branch with more under it, its last, the
  // line past a deeper row, none".
  func testBlockedsTreeGuides() throws {
    // web#1; web#2 and web#3 under it, web#4 under web#3 and web#5 under web#2; then a chain of its own.
    XCTAssertEqual(Lists.treeGuides([0, 1, 2, 1, 2, 0, 1]), [[], [.tee], [.rail, .end], [.end], [.gap, .end], [], [.end]])
    XCTAssertEqual(Lists.treeGuides([0, 0]), [[], []], "rows of their own draw nothing")
    XCTAssertEqual(Lists.treeGuides([]), [])
    let q: QueueView = try Fixture.decode("queue")
    let drawn = Lists.treeGuides((q.sections?.blocked ?? []).map { $0.depth ?? 0 })
    XCTAssertEqual(Array(drawn[2...4]), [[], [.end], [.gap, .end]], "billing#2300, #2302 under it, #2303 under that")
    XCTAssertEqual(Array(drawn[7...10]), [[], [.tee], [.end], [.gap, .end]], "web#2306 with two under it, the second with one of its own")
  }

  // RowMenu.tsx's MOVES: one section up or down, for an active card on the Inbox.
  func testWhereARowCanMove() throws {
    let card = { (more: String) in
      try DeskJSON.decoder().decode(Card.self, from: Data(#"{"id":"a/b#1","kind":"pr","repo":"a/b","number":1,"title":"t"\#(more)}"#.utf8))
    }
    XCTAssertEqual(Lists.moves(try card(#","section":"urgent","status":"active""#)), ["standard"])
    XCTAssertEqual(Lists.moves(try card(#","section":"standard","status":"active""#)), ["urgent", "fyi"])
    XCTAssertEqual(Lists.moves(try card(#","section":"fyi","status":"active""#)), ["standard"])
    XCTAssertEqual(Lists.moves(try card(#","status":"active""#)), [], "not on the Inbox")
    XCTAssertEqual(Lists.moves(try card(#","section":"standard","status":"snoozed""#)), [])
    XCTAssertEqual(Lists.moves(try card(#","section":"standard","status":"active","inflight":true"#)), [], "in Merging")
    XCTAssertEqual(Lists.moves(try card(#","section":"someday","status":"active""#)), [], "a newer desk's section")
    let q: QueueView = try Fixture.decode("queue")
    XCTAssertEqual(q.inbox?.urgent.first.map(Lists.moves), ["standard"])
    XCTAssertEqual(q.inbox?.fyi.first?.section, "fyi")
    XCTAssertNil(q.sections?.blocked.first?.section)
  }

  // Queue.tsx's cut: five of seven, all of six, all once asked or while filtering.
  func testFYIShowsItsFirstFive() {
    XCTAssertEqual(Lists.fyiCut(7, all: false, filtering: false), 5)
    XCTAssertEqual(Lists.fyiCut(40, all: false, filtering: false), 5)
    XCTAssertNil(Lists.fyiCut(6, all: false, filtering: false), "one row is never hidden alone")
    XCTAssertNil(Lists.fyiCut(5, all: false, filtering: false))
    XCTAssertNil(Lists.fyiCut(7, all: true, filtering: false))
    XCTAssertNil(Lists.fyiCut(7, all: false, filtering: true))
  }

  func testTheArchive() throws {
    let q: QueueView = try Fixture.decode("queue")
    let archive = Lists.archive(q)
    XCTAssertEqual(archive.count, 4)
    let times = archive.map { $0.resolvedAt ?? $0.doneAt ?? "" }
    XCTAssertEqual(times, times.sorted(by: >))
    XCTAssertEqual(Lists.cleared(q).count, 9)
    XCTAssertEqual(Lists.archiveNote(archive.first { $0.resolved == nil }!), "done: back when someone else acts")
    XCTAssertEqual(Lists.hiddenNote(try card()), "hidden by your rules")
  }

  func testNotices() throws {
    XCTAssertTrue(Notices.of(Conditions()).isEmpty, "nothing is said while all is well")

    let local = Notices.of(Conditions(offline: true, local: true, overview: nil))
    XCTAssertEqual(local.map(\.title), ["The desk isn't running"])
    XCTAssertEqual(local[0].text, "Start it with `desk serve` or open the desktop app.")
    XCTAssertEqual(local[0].fixLabel, "Retry")
    let away = Notices.of(Conditions(offline: true))
    XCTAssertEqual(away.map(\.title), ["The desk can't be reached"])
    XCTAssertEqual(away[0].text?.contains("Tailscale"), true)

    let overview = { (json: String) in try DeskJSON.decoder().decode(Overview.self, from: Data(json.utf8)) }
    let failed = Notices.of(Conditions(overview: try overview(#"{"sync_error":"GitHub: 502 Bad Gateway","syncing":true,"connectors":[{"status":"error"}]}"#)))
    XCTAssertEqual(failed.map(\.title), ["Sync failed"])
    XCTAssertEqual(failed[0].text, "GitHub: 502 Bad Gateway")
    XCTAssertEqual(failed[0].fixLabel, "Syncing…")
    XCTAssertTrue(failed[0].busy)
    XCTAssertEqual(failed[0].tone, .red)

    let limited = Notices.of(
      Conditions(overview: try overview(#"{"sync_error":"rate limited","connectors":[{"status":"paused"}],"rate_limit":{"remaining":0,"reset_at":"2026-10-27T14:30:00Z"}}"#)),
      now: now)
    XCTAssertEqual(limited.map(\.title), ["GitHub's rate limit is used up"])
    XCTAssertEqual(limited[0].tone, .amber)
    XCTAssertNil(limited[0].fix, "a retry would only seem to run")
    XCTAssertEqual(limited[0].text?.hasPrefix("Syncing starts again at "), true)

    let rules = Notices.of(Conditions(overview: try overview(#"{"config_errors":[{"path":"a","message":"b"},{"path":"c","message":"d"}]}"#)))
    XCTAssertEqual(rules.map(\.title), ["Your rules have 2 errors"])
    XCTAssertEqual(Notices.of(Conditions(broken: "config has errors: boards[0]: nope")).first?.text, "There's nothing on your desk until they do. boards[0]: nope")

    let paused = try DeskJSON.decoder().decode(QueueView.Paused.self, from: Data(#"{"who":"claude","why":"Claude Code isn't logged in."}"#.utf8))
    XCTAssertEqual(Notices.of(Conditions(paused: paused, agent: "Codex")).map(\.title), ["Codex is paused"])
    // While the desk is unreachable, what it said last is stale: only that it's down is said.
    XCTAssertEqual(Notices.of(Conditions(offline: true, paused: paused)).count, 1)
    XCTAssertEqual(Notices.of(Conditions(starting: "desk is starting; the first sync can take a minute")).map(\.title), ["The desk is starting"])

    // A read the desk refused: its words, and alone, since what it said before is stale.
    let refused = Notices.of(Conditions(refused: "forbidden host", paused: paused))
    XCTAssertEqual(refused.map(\.title), ["Can't read the desk"])
    XCTAssertEqual(refused[0].text, "Forbidden host.")
    XCTAssertEqual(refused[0].tone, .red)
    XCTAssertEqual(Notices.of(Conditions(offline: true, refused: "forbidden host")).map(\.title), ["The desk can't be reached"])
  }

  func testProseSplitsAtLinks() {
    let parts = Prose.urls("See https://github.com/a/b/pull/12#r1, and (https://example.com/x). Done")
    XCTAssertEqual(parts.map(\.0), ["See ", "https://github.com/a/b/pull/12#r1", ", and (", "https://example.com/x", "). Done"])
    XCTAssertEqual(parts.map(\.1), [false, true, false, true, false])
    XCTAssertEqual(InquiryPage.place("https://www.github.com/me/notes-app/pull/12#discussion_r1"), "github.com/me/notes-app/pull/12#discussion_r1")
  }

  // An opened page's one call to action: the row's own first, then what the item is there for.
  func testAPagesCallToAction() throws {
    let queue: QueueView = try Fixture.decode("queue")
    let cards = (queue.inbox?.urgent ?? []) + (queue.inbox?.standard ?? []) + (queue.inbox?.fyi ?? [])
    let act = { (id: String) in cards.first { $0.id == id }?.act(open: true) }
    XCTAssertEqual(act("acme/api#4127"), "approve", "someone else's PR")
    XCTAssertEqual(act("me/notes-app#12"), "reply", "the row's own call to action wins")
    XCTAssertEqual(act("acme/web#2303"), "ready")
    XCTAssertEqual(act("acme/worker#875"), "handoff", "yours, approved")
    XCTAssertEqual(act("acme/worker#860"), "comment", "an issue")
    XCTAssertNil(act("acme/api#4154"), "yours with changes requested: nothing to press but More")
    XCTAssertNil(cards.first { $0.id == "acme/api#4127" }?.act(open: false), "closed or merged")
    for key in ["ready", "reviewers", "reply", "merge", "approve", "comment", "handoff"] { XCTAssertNotNil(Words.act[key], key) }
    XCTAssertEqual(Words.act["ready"], Words.cta["ready"], "a row's call to action keeps the row's words")
  }

  // An issue's page: what kind its pre-review says it is, who placed it and how you were asked (Detail.tsx).
  func testAnIssuesWords() throws {
    XCTAssertEqual(Words.issueKind("bug"), "A bug")
    XCTAssertEqual(Words.issueKind("feature"), "A feature request")
    XCTAssertEqual(Words.issueKind("question"), "A question")
    XCTAssertEqual(Words.issueKind("other"), "An issue")
    XCTAssertEqual(Words.issueKind(nil), "An issue")
    XCTAssertEqual(Words.issueKind("epic"), "An issue", "a kind a newer desk has")
    XCTAssertEqual(Words.act["fix"], "Make PR with fix")

    XCTAssertEqual(Words.placedBy("claude", agent: "Codex"), "sorted by Codex")
    XCTAssertEqual(Words.placedBy("hard", agent: "Claude"), "placed by a hard rule")
    XCTAssertEqual(Words.placedBy("pin", agent: "Claude"), "kept up by its pin")
    XCTAssertEqual(Words.placedBy("automation", agent: "Claude"), "sorted by an automation")
    XCTAssertNil(Words.placedBy(nil, agent: "Claude"))

    typealias Me = ItemDetail.Signals.Me
    XCTAssertEqual(Words.asked(Me(assignee: true, requested: false)), "assigned to you")
    XCTAssertEqual(Words.asked(Me(requested: false)), "not requested")
    XCTAssertEqual(Words.asked(Me(author: true)), "your PR")
    XCTAssertEqual(
      Words.asked(Me(requested: true, requestedDirect: true, requestedCodeowner: true, requestedBy: "dana", requestedByBot: false, requestedHours: 3.4)),
      "you, by name, by dana, CODEOWNERS, 3h ago")
    XCTAssertEqual(
      Words.asked(Me(requested: true, requestedDirect: false, requestedTeam: "acme/api", requestedBy: "triage", requestedByBot: true, requestedHours: 0.5)),
      "your team @acme/api, by triage (bot), 30m ago")
    XCTAssertEqual(Words.asked(Me(requested: true, requestedDirect: true, requestedBy: "", requestedHours: 72)), "you, by name, 3d ago")
    XCTAssertEqual(Words.asked(Me(requested: true, requestedDirect: true, requestedHours: -1)), "you, by name")

    let d: ItemDetail = try Fixture.decode("item-issue")
    XCTAssertTrue(Words.says(d.card.why ?? "", Words.asked(try XCTUnwrap(d.signals?.me))), "its why already says it")
  }

  // What reviewers said: where a conversation is, its one line and your agent's take (Conversation.tsx).
  func testAConversationsWords() throws {
    func convo(_ json: String) throws -> Conversation { try DeskJSON.decoder().decode(Conversation.self, from: Data(json.utf8)) }
    XCTAssertEqual(Words.place(try convo(#"{"id":"a","path":"src/auth.ts","line":42}"#)), "src/auth.ts:42")
    XCTAssertEqual(Words.place(try convo(#"{"id":"a","path":"src/auth.ts","line":42,"outdated":true}"#)), "src/auth.ts:42, outdated")
    XCTAssertEqual(Words.place(try convo(#"{"id":"a","path":"src/auth.ts","line":null,"outdated":true}"#)), "src/auth.ts, outdated")
    XCTAssertEqual(Words.place(try convo(#"{"id":"a","kind":"comment","path":null}"#)), "on the PR")

    XCTAssertEqual(Words.firstLine("\n  Can this ship?  \n\nThe release wants it."), "Can this ship?")
    XCTAssertEqual(Words.firstLine(String(repeating: "a", count: 160)), String(repeating: "a", count: 160), "160 is whole")
    let cut = Words.firstLine(String(repeating: "a", count: 161) + "\nmore")
    XCTAssertEqual(cut, String(repeating: "a", count: 159) + "…")
    XCTAssertEqual(cut.count, 160)
    XCTAssertEqual(Words.firstLine(nil), "")
    let bot = "### Possible null dereference\n\n`local` may be undefined.\n\n<details><summary>Evidence</summary>\n\n- `merge()` reads it\n\n</details>\n\n<sub>Found by bugbot</sub>\n<!-- finding:v1 -->"
    XCTAssertEqual(Words.firstLine(bot), "Possible null dereference", "a heading's hashes aren't words")
    XCTAssertEqual(
      Words.saidText(bot), "Possible null dereference\n\n`local` may be undefined.\n\nEvidence\n\n- `merge()` reads it\n\nFound by bugbot",
      "no tags, no comments, code kept")
    XCTAssertEqual(Words.saidText("if a < b && c > d then #1"), "if a < b && c > d then #1", "not every angle is a tag")

    let read = try convo(#"{"id":"a","comments":[{"id":"1","author":"dana","body":"Long.\nMore."}],"take":{"gist":"The gist","take":"x"}}"#)
    XCTAssertEqual(Words.gist(read), "The gist", "your agent's, when it has read it")
    let unread = try convo(#"{"id":"a","comments":[{"id":"1","author":"dana","body":"First."},{"id":"2","author":"kai","body":"Last line.\nMore."}]}"#)
    XCTAssertEqual(Words.gist(unread), "Last line.", "else the last comment's first line")
    XCTAssertEqual(Words.saidLabel(read), "What dana wrote")
    XCTAssertEqual(Words.saidLabel(unread), "What was said")
    XCTAssertEqual(Words.replyTo("Reply", unread, me: "me"), "Reply to kai")
    XCTAssertEqual(Words.replyTo("Reply", unread, me: "Kai"), "Reply to dana", "not to yourself, when you spoke last")
    XCTAssertEqual(Words.replyTo("Sent your reply", read, me: "dana"), "Sent your reply", "your own thread: nobody to name")

    var take = Words.takeSplit("Valid concern: nothing prunes it: see `merge()`")
    XCTAssertEqual(take.call, "Valid concern")
    XCTAssertEqual(take.rest, "nothing prunes it: see `merge()`", "only the first one splits")
    take = Words.takeSplit("Nothing to do here")
    XCTAssertNil(take.call, "no call: all plain")
    XCTAssertEqual(take.rest, "Nothing to do here")
    take = Words.takeSplit("At 10:30 it ran")
    XCTAssertNil(take.call, "a colon inside a word isn't one")
  }
}
