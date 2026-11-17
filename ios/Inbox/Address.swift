import Foundation

// Where the desk is: https://<machine>.<tailnet>.ts.net over Tailscale (paired, with a token), or http://localhost:<port>
// on the desk's own computer (the Simulator, the mock: no code and no token).
struct DeskAddress: Equatable, Sendable {
  let url: URL  // scheme, host and port only

  var host: String { url.host() ?? "" }
  var isLocal: Bool { ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) }
  var text: String { url.absoluteString }
  var isDemo: Bool { self == DemoDesk.address }  // test mode's made-up desk (Demo.swift)

  enum Unreadable: Error, Equatable {
    case empty, notAnAddress, plainHTTP, notAPairingLink

    var words: String {
      switch self {
      case .empty: "Type the desk's address: Pair a device shows it, in Settings → Network on the desk's computer."
      case .notAnAddress: "That isn't an address. It looks like https://machine.tailnet.ts.net."
      case .plainHTTP: "Use the desk's https address: plain http only works for localhost."
      case .notAPairingLink:
        "That isn't a desk's pairing code. Scan the one Pair a device shows, in Settings → Network on the desk's computer."
      }
    }
  }

  // What was typed or pasted: an address with or without its scheme, or the whole pairing link (https://<name>/pair#CODE),
  // which carries the code too.
  static func parse(_ typed: String) -> Result<(address: DeskAddress, code: String?), Unreadable> {
    var s = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return .failure(.empty) }
    if !s.contains("://") {
      let host = s.split(whereSeparator: { "/:#?".contains($0) }).first.map(String.init)?.lowercased() ?? ""
      s = (["localhost", "127.0.0.1"].contains(host) ? "http://" : "https://") + s
    }
    guard let parts = URLComponents(string: s), let scheme = parts.scheme?.lowercased(), let host = parts.host, !host.isEmpty,
      !host.contains(" "), parts.user == nil, parts.password == nil
    else { return .failure(.notAnAddress) }
    guard scheme == "https" || scheme == "http" else { return .failure(.notAnAddress) }
    var base = URLComponents()
    base.scheme = scheme
    base.host = host.lowercased()
    base.port = parts.port
    guard let url = base.url else { return .failure(.notAnAddress) }
    let address = DeskAddress(url: url)
    if scheme == "http" && !address.isLocal { return .failure(.plainHTTP) }
    let code = parts.path.hasPrefix("/pair") ? parts.fragment.flatMap(PairingCode.normalize) : nil
    return .success((address, code))
  }

  // What the camera read: the link only when it's a desk's pairing link with a code's shape. Anything else (a website,
  // a bare address) never reaches the desk, so it never spends a try.
  static func scanned(_ text: String) -> Result<String, Unreadable> {
    let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard case .success(let parsed) = parse(link), parsed.code != nil else { return .failure(.notAPairingLink) }
    return .success(link)
  }
}

enum PairingCode {
  static let alphabet = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

  // As the desk reads it: upper-cased, letters and digits only. Nil unless it has a code's shape, so a slip of the thumb
  // never spends a try (any try burns the code, and tries are rate-limited).
  static func normalize(_ typed: String) -> String? {
    let code = typed.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    return code.count == 8 && code.allSatisfy(alphabet.contains) ? code : nil
  }
}
