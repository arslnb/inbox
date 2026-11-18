import XCTest

@testable import Inbox

// Test mode's made-up desk (Demo.swift): it answers what the app asks from Demo.json, and its writes change only it.
final class DemoTests: XCTestCase {
  private let client = APIClient(address: DemoDesk.address, token: nil, session: DemoDesk.session)

  override func setUp() { DemoDesk.reset() }
  override func tearDown() { DemoDesk.reset() }

  private func inbox() async throws -> [String] {
    let q = try await client.queue()
    return ((q.inbox?.urgent ?? []) + (q.inbox?.standard ?? []) + (q.inbox?.fyi ?? [])).map(\.id)
  }

  func testEveryListAndPageReads() async throws {
    _ = try await client.health()
    _ = try await client.overview()
    let ids = try await inbox()
    XCTAssertGreaterThan(ids.count, 10)
    let merging = try await client.inflight().rows
    XCTAssertFalse(merging.isEmpty)
    let asks = try await client.asks().asks
    XCTAssertFalse(asks.isEmpty)
    let q = try await client.queue()
    XCTAssertFalse(q.inquiries.isEmpty)
    for inquiry in q.inquiries { _ = try await client.inquiry(inquiry.id) }
    // Every row opens, and every PR's review reads.
    for id in ids {
      let item = try await client.item(id)
      if item.card.kind != "issue" { _ = try await client.review(id, ahead: true) }
    }
  }

  func testItsTimesMoveWithTheClock() async throws {
    let q = try await client.queue()
    let newest = try XCTUnwrap((q.inbox?.urgent ?? []).compactMap { Words.date($0.activityAt) }.max())
    XCTAssertLessThan(abs(newest.timeIntervalSinceNow), 3 * 86_400, "however long ago Demo.json was recorded")
  }

  func testWritesTakeItemsOffAndUndoBringsThemBack() async throws {
    let id = "acme/api#4127"
    var ids = try await inbox()
    XCTAssertTrue(ids.contains(id))
    _ = try await client.approve(id, head: "abc")
    ids = try await inbox()
    XCTAssertFalse(ids.contains(id), "an id with a slash in it is read from the path whole")

    let other = try XCTUnwrap(ids.first)
    let done = try await client.act(other, "done")
    ids = try await inbox()
    XCTAssertFalse(ids.contains(other))
    _ = try await client.undo(seq: try XCTUnwrap(done.undoSeq))
    ids = try await inbox()
    XCTAssertTrue(ids.contains(other))

    DemoDesk.reset()
    ids = try await inbox()
    XCTAssertTrue(ids.contains(id))
  }

  func testAnAskIsAnsweredAndANoteShows() async throws {
    let before = try await client.asks().asks.count
    let asked = try await client.ask("what's left?", about: ChatAbout())
    XCTAssertEqual(asked.ask?.text, "what's left?")
    let asks = try await client.asks().asks
    XCTAssertEqual(asks.count, before + 1)
    XCTAssertNotNil(asks.last?.answer, "test mode answers at once: no agent runs")

    let note = try await client.saveNote(nil, text: "Read the planner change", remind: "", section: "urgent")
    let noteId = try XCTUnwrap(note.note?.id)
    var urgent = try await client.queue().notes?.urgent.first?.id
    XCTAssertEqual(urgent, noteId)
    try await client.doneNote(noteId)
    urgent = try await client.queue().notes?.urgent.first?.id
    XCTAssertNotEqual(urgent, noteId)
  }

  func testNothingLeavesThePhone() {
    XCTAssertTrue(DemoDesk.canInit(with: URLRequest(url: DemoDesk.address.url.appending(path: "/api/queue"))))
    XCTAssertFalse(DemoDesk.canInit(with: URLRequest(url: URL(string: "https://github.com/acme/api/pull/4127")!)))
    XCTAssertTrue(DemoDesk.address.isDemo)
    XCTAssertEqual(try? DeskAddress.parse(DemoDesk.address.text).get().address.isDemo, true)
  }
}
