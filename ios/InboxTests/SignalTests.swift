import XCTest

@testable import Inbox

// RowIcons.tsx's factsOf(), and the row's signal: its AI review's risk, as the review shows it.
final class SignalTests: XCTestCase {
  private func card(_ json: String, kind: String = "pr") throws -> Card {
    let base = #"{"id":"a/b#1","repo":"acme/api","number":1,"title":"t","kind":""# + kind + #"","#
    return try DeskJSON.decoder().decode(Card.self, from: Data("\(base)\(json)}".utf8))
  }

  func testAPRWithNothingAgainstIt() throws {
    let c = try card(#""stage":"approved","ci":"green","preflight":{"state":"ready","verdict":"skip","risk":"low"},"size":{"add":12,"del":3}"#)
    let facts = Signal.facts(c, stage: true)
    XCTAssertEqual(facts.map(\.said), ["Approved", "CI passing", "Low risk, skip it", "Tiny change"])
    XCTAssertEqual(Signal.lit(c), 4)
    XCTAssertEqual(Signal.said(facts), "Approved. CI passing. Low risk, skip it. Tiny change")
  }

  func testTheSignalIsTheRiskAlone() throws {
    let c = try card(#""stage":"draft","ci":"red","verdict":"look","risk":"high","size":{"add":500,"del":300}"#)
    let facts = Signal.facts(c, stage: true)
    XCTAssertEqual(facts.map(\.said), ["Draft", "CI failing", "High risk, look closely", "Large change"])
    XCTAssertEqual(Signal.lit(c), 1, "high risk")
    let big = try card(#""stage":"draft","ci":"red","preflight":{"risk":"low"},"size":{"add":462,"del":18}"#)
    XCTAssertEqual(Signal.lit(big), 4, "low risk, whatever its stage, CI or size")
    XCTAssertEqual(Signal.lit(try card(#""ci":"pending","preflight":{"risk":"medium"}"#)), 2)
  }

  func testNoReviewYetIsGrey() throws {
    let c = try card(#""stage":"changes requested","ci":"none""#)
    XCTAssertEqual(Signal.facts(c, stage: false).map(\.said), ["No checks", "No AI review yet"], "off the Inbox, no stage; no size, no fact")
    XCTAssertEqual(Signal.lit(c), 0)
    XCTAssertEqual(Signal.facts(try card(#""ci":"red""#, kind: "issue"), stage: true), [], "an issue has no signal")
  }
}
