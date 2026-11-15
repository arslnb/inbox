import XCTest

@testable import Inbox

final class AddressTests: XCTestCase {
  private func parse(_ s: String) -> (address: DeskAddress, code: String?)? {
    if case .success(let p) = DeskAddress.parse(s) { p } else { nil }
  }

  private func failure(_ s: String) -> DeskAddress.Unreadable? {
    if case .failure(let e) = DeskAddress.parse(s) { e } else { nil }
  }

  func testATailnetAddress() {
    let typed = parse("https://gregs-mac.tail1234.ts.net")
    XCTAssertEqual(typed?.address.text, "https://gregs-mac.tail1234.ts.net")
    XCTAssertEqual(typed?.address.isLocal, false)
    XCTAssertNil(typed?.code)
    // Typed without its scheme, with stray space, a trailing slash or capitals: the same address.
    XCTAssertEqual(parse("  gregs-mac.tail1234.ts.net\n")?.address.text, "https://gregs-mac.tail1234.ts.net")
    XCTAssertEqual(parse("https://Gregs-Mac.Tail1234.ts.net/")?.address.text, "https://gregs-mac.tail1234.ts.net")
    XCTAssertEqual(parse("gregs-mac.tail1234.ts.net/some/page?x=1")?.address.text, "https://gregs-mac.tail1234.ts.net")
  }

  // The whole pairing link, as desk pair prints it, carries the address and the code.
  func testThePairingLink() {
    let link = parse("https://gregs-mac.tail1234.ts.net/pair#ABCD-2345")
    XCTAssertEqual(link?.address.text, "https://gregs-mac.tail1234.ts.net")
    XCTAssertEqual(link?.code, "ABCD2345")
    XCTAssertEqual(parse("gregs-mac.tail1234.ts.net/pair#abcd-2345")?.code, "ABCD2345")
    XCTAssertNil(parse("https://gregs-mac.tail1234.ts.net/pair#nope")?.code, "a fragment that isn't a code is no code")
    XCTAssertNil(parse("https://gregs-mac.tail1234.ts.net/#ABCD-2345")?.code, "only the pairing page's fragment is a code")
  }

  // The desk's own computer: plain http, any port, no code.
  func testLocalhost() {
    XCTAssertEqual(parse("http://localhost:47823")?.address.text, "http://localhost:47823")
    XCTAssertEqual(parse("http://localhost:47823")?.address.isLocal, true)
    XCTAssertEqual(parse("http://127.0.0.1:47841/")?.address.isLocal, true)
    XCTAssertEqual(parse("localhost:47841")?.address.text, "http://localhost:47841", "no scheme on localhost means http")
    XCTAssertEqual(parse("127.0.0.1:47823")?.address.text, "http://127.0.0.1:47823")
    XCTAssertEqual(parse("http://[::1]:47823")?.address.isLocal, true)
  }

  func testWhatIsNotAnAddress() {
    XCTAssertEqual(failure(""), .empty)
    XCTAssertEqual(failure("   "), .empty)
    XCTAssertEqual(failure("http://gregs-mac.tail1234.ts.net"), .plainHTTP)
    XCTAssertEqual(failure("ftp://gregs-mac.tail1234.ts.net"), .notAnAddress)
    XCTAssertEqual(failure("https://"), .notAnAddress)
    XCTAssertEqual(failure("https://user:secret@gregs-mac.tail1234.ts.net"), .notAnAddress)
    XCTAssertEqual(failure("my desk"), .notAnAddress)
  }

  // The camera's reading: only a desk's pairing link passes, so nothing else is ever sent anywhere.
  func testWhatWasScanned() {
    func scanned(_ s: String) -> String? {
      if case .success(let link) = DeskAddress.scanned(s) { link } else { nil }
    }
    for link in [
      "https://gregs-mac.tail1234.ts.net/pair#ABCD-2345", "https://gregs-mac.tail1234.ts.net/pair#abcd-2345",
      "https://gregs-mac.tail1234.ts.net/pair#ABCD2345", "HTTPS://GREGS-MAC.TAIL1234.TS.NET/pair#abcd2345",
      "http://localhost:47841/pair#ABCD-2345",
    ] {
      XCTAssertEqual(scanned(link), link)
    }
    XCTAssertEqual(scanned(" https://gregs-mac.tail1234.ts.net/pair#ABCD-2345\n"), "https://gregs-mac.tail1234.ts.net/pair#ABCD-2345")
    // Any name passes, a ts.net one or not (a desk can be served elsewhere, and Funnel's names are public anyway): so
    // the connect screen says the name and waits for Connect before anything is sent there.
    XCTAssertNotNil(scanned("https://not-your-desk.example/pair#ABCD2345"))
    for other in [
      "https://example.com", "WIFI:T:WPA;S:home;P:secret;;", "https://gregs-mac.tail1234.ts.net", "http://localhost:47841",
      "https://gregs-mac.tail1234.ts.net/pair#nope", "https://gregs-mac.tail1234.ts.net/pair", "https://gregs-mac.tail1234.ts.net/#ABCD-2345",
      "http://gregs-mac.tail1234.ts.net/pair#ABCD-2345", "ABCD-2345", "just some words", "",
    ] {
      XCTAssertEqual(DeskAddress.scanned(other), .failure(.notAPairingLink), other)
    }
    XCTAssertEqual(
      DeskAddress.Unreadable.notAPairingLink.words,
      "That isn't a desk's pairing code. Scan the one Pair a device shows, in Settings → Network on the desk's computer.")
  }

  // As the desk reads a code: any case, with or without its dash; never one that can't be a code.
  func testCodes() {
    XCTAssertEqual(PairingCode.normalize("ABCD-2345"), "ABCD2345")
    XCTAssertEqual(PairingCode.normalize("abcd 2345"), "ABCD2345")
    XCTAssertEqual(PairingCode.normalize(" abcd2345 "), "ABCD2345")
    XCTAssertNil(PairingCode.normalize("ABCD-234"), "too short")
    XCTAssertNil(PairingCode.normalize("ABCD-23456"), "too long")
    XCTAssertNil(PairingCode.normalize("ABCD-2340"), "no 0 in the alphabet")
    XCTAssertNil(PairingCode.normalize("ABCO-2345"), "no O")
    XCTAssertNil(PairingCode.normalize("ABCI-2341"), "no I, no 1")
    XCTAssertNil(PairingCode.normalize(""))
  }
}
