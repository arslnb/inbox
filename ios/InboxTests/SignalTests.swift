import XCTest

@testable import Inbox

// RowIcons.tsx's factsOf() and its signal: one bar lit for each fact with nothing against it.
final class SignalTests: XCTestCase {
  private func card(_ json: String, kind: String = "pr") throws -> Card {
    let base = #"{"id":"a/b#1","repo":"acme/api","number":1,"title":"t","kind":""# + kind + #"","#
    return try DeskJSON.decoder().decode(Card.self, from: Data("\(base)\(json)}".utf8))
  }

  func testAPRWithNothingAgainstIt() throws {
    let c = try card(#""stage":"approved","ci":"green","preflight":{"state":"ready","verdict":"skip","risk":"low"},"size":{"add":12,"del":3}"#)
    let facts = Signal.facts(c, stage: true)
    XCTAssertEqual(facts.map(\.said), ["Approved", "CI passing", "Low risk, skip it", "Tiny change"])
    XCTAssertEqual(Signal.lit(facts), 4)
    XCTAssertEqual(Signal.said(facts), "Approved. CI passing. Low risk, skip it. Tiny change")
  }

  func testEachFactAgainstItTakesABar() throws {
    let c = try card(#""stage":"draft","ci":"red","verdict":"look","size":{"add":500,"del":300}"#)
    let facts = Signal.facts(c, stage: true)
    XCTAssertEqual(facts.map(\.said), ["Draft", "CI failing", "High risk, look closely", "Large change"])
    XCTAssertEqual(Signal.lit(facts), 0)
    XCTAssertEqual(Signal.lit(Signal.facts(try card(#""ci":"pending","preflight":{"risk":"medium"}"#), stage: true)), 2, "running CI and a medium risk")
  }

  func testNothingToSayCountsForIt() throws {
    let facts = Signal.facts(try card(#""stage":"changes requested","ci":"none""#), stage: false)
    XCTAssertEqual(facts.map(\.said), ["No checks", "No AI review yet"], "off the Inbox, no stage; no size, no fact")
    XCTAssertEqual(Signal.lit(facts), 4)
    XCTAssertEqual(Signal.facts(try card(#""ci":"red""#, kind: "issue"), stage: true), [], "an issue has no signal")
  }
}
