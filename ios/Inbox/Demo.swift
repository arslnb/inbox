import Foundation

// Test mode: a desk made up inside the app, to try it without one (and for App Review). Every request is answered from
// Demo.json, the mock desk recorded by `npm run ios:demo`; a write changes only what this desk shows, and nothing leaves
// the phone. Its times move with the clock, so the items stay as fresh as they were when recorded.
final class DemoDesk: URLProtocol, @unchecked Sendable {
  static let address = DeskAddress(url: URL(string: "https://test-mode.invalid")!)

  static let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.protocolClasses = [DemoDesk.self]
    return URLSession(configuration: c)
  }()

  // A fresh desk again: everything done in test mode comes back.
  static func reset() { state.reset() }

  private static let state = DemoState()

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == address.host }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let method = request.httpMethod ?? "GET"
    let path = url.path(percentEncoded: false)
    if method == "GET" && path == "/api/events" {
      reply(200, type: "text/event-stream", Data(": test mode\n\n".utf8), finish: false)
      DemoDesk.state.listen(self)
      return
    }
    let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
    let body = (request.httpBody ?? request.httpBodyStream.map(Self.read)).flatMap {
      try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    } ?? [:]
    let (status, answer) =
      method == "GET" ? DemoDesk.state.read(path, id: id) : DemoDesk.state.write(path, body: body)
    let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data("{}".utf8)
    reply(status, type: "application/json", data, finish: true)
  }

  override func stopLoading() { DemoDesk.state.forget(self) }

  fileprivate func update() { client?.urlProtocol(self, didLoad: Data("event: update\ndata: {}\n\n".utf8)) }

  private func reply(_ status: Int, type: String, _ data: Data, finish: Bool) {
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    if finish { client?.urlProtocolDidFinishLoading(self) }
  }

  private static func read(_ stream: InputStream) -> Data {
    var data = Data()
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let n = stream.read(&buffer, maxLength: buffer.count)
      if n <= 0 { break }
      data.append(buffer, count: n)
    }
    return data
  }
}

// What test mode's desk holds: the recorded answers, and what was done to them since.
private final class DemoState: @unchecked Sendable {
  private let lock = NSLock()
  private var routes: [String: Any]?
  private var gone: Set<String> = []  // done, snoozed, approved, merged, answered: off the lists
  private var undos: [Int: String] = [:]
  private var notes: [[String: Any]] = []
  private var asks: [[String: Any]] = []
  private var streams: [DemoDesk] = []
  private var count = 0
  private static let verbs: Set<String> = [
    "approve", "comment", "reply", "inline", "ready", "reviewers", "viewed", "reviewer", "ai", "analyze", "fix", "block", "unblock",
    "answer", "kick", "open", "done",
  ]

  func reset() {
    lock.withLock {
      gone = []
      undos = [:]
      notes = []
      asks = []
    }
  }

  func listen(_ stream: DemoDesk) { lock.withLock { streams.append(stream) } }
  func forget(_ stream: DemoDesk) { lock.withLock { streams.removeAll { $0 === stream } } }

  func read(_ path: String, id: String?) -> (Int, Any) {
    lock.withLock {
      let key = id.map { "\(path)?id=\($0)" } ?? path
      guard let found = loaded()[key] else { return (404, ["error": "test mode has nothing at \(key)"]) }
      switch path {
      case "/api/queue", "/api/inflight", "/api/overview": return (200, withNotes(without(found)))
      case "/api/asks": return (200, withAsks(found))
      default: return (200, found)
      }
    }
  }

  func write(_ path: String, body: [String: Any]) -> (Int, Any) {
    let answer: [String: Any] = lock.withLock {
      // /api/<what>/<id>/<verb>, where an id may hold a "/" (acme/api#4127); /api/act and /api/github carry it in the body.
      let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
      let verb = parts.count > 3 && Self.verbs.contains(parts[parts.count - 1])
      let target = parts.count > 2 ? parts[2..<(verb ? parts.count - 1 : parts.count)].joined(separator: "/") : (body["id"] as? String ?? "")
      let action = body["action"] as? String ?? ""
      count += 1
      switch (parts.dropFirst().first ?? "", verb ? parts[parts.count - 1] : "") {
      case ("act", _):
        if ["restore", "unmute", "takeback"].contains(action) {
          gone.remove(target)
          return ["ok": true]
        }
        guard action != "seen" else { return ["ok": true] }
        gone.insert(target)
        undos[count] = target
        return ["ok": true, "undo_seq": count]
      case ("undo", _):
        let seq = body["seq"] as? Int ?? 0
        if let id = undos.removeValue(forKey: seq) { gone.remove(id) }
        return ["ok": true]
      case ("github", _):
        if ["merge", "close", "request_changes"].contains(action) { gone.insert(target) }
        return ["ok": true]
      case ("review", "approve"), ("review", "ready"), ("inquiries", "answer"), ("sessions", "kick"):
        gone.insert(target)
        return ["ok": true, "done": true]
      case ("review", "reviewers"):
        if body["keep"] as? Bool != true { gone.insert(target) }
        return ["ok": true]
      case ("notes", "done"):
        gone.insert(target)
        notes.removeAll { $0["id"] as? String == target }
        return ["ok": true]
      case ("notes", _):
        return ["ok": true, "note": note(parts.count > 2 ? target : nil, body)]
      case ("ask", _):
        return ["ok": true, "ask": ask(body)]
      default:
        return ["ok": true]
      }
    }
    let listening = lock.withLock { streams }
    for stream in listening { stream.update() }
    return (200, answer)
  }

  // A note written in test mode: kept at the top of the section it was put in.
  private func note(_ id: String?, _ body: [String: Any]) -> [String: Any] {
    let text = body["text"] as? String ?? ""
    let section = body["section"] as? String ?? "standard"
    if let id, let i = notes.firstIndex(where: { $0["id"] as? String == id }) {
      notes[i]["text"] = text
      notes[i]["section"] = section
      return notes[i]
    }
    if let id {
      gone.insert(id)  // a recorded note, changed: its new words take its place
    }
    let note: [String: Any] = [
      "id": "test-note-\(count)", "at": iso(Date()), "text": text, "remind_at": NSNull(), "reminded_at": NSNull(),
      "section": section,
    ]
    notes.insert(note, at: 0)
    return note
  }

  // Your words to your agent, answered at once with what test mode can say.
  private func ask(_ body: [String: Any]) -> [String: Any] {
    let now = iso(Date())
    let ask: [String: Any] = [
      "id": "test-ask-\(count)", "at": now, "text": body["text"] as? String ?? "", "item_id": body["item_id"] ?? NSNull(),
      "thread_id": body["thread_id"] ?? NSNull(), "thread_url": body["thread_url"] ?? NSNull(),
      "answer": [
        "text": "This is test mode, so no agent is running. Connected to your desk, your agent (Claude Code, Codex or OpenCode on your computer) answers here.",
        "at": now,
      ],
    ]
    asks.append(ask)
    return ask
  }

  // The lists without what was done in test mode, anywhere in them.
  private func without(_ v: Any) -> Any {
    if let list = v as? [Any] {
      return list.compactMap { x -> Any? in
        if let d = x as? [String: Any], let id = d["id"] as? String, gone.contains(id) { return nil }
        return without(x)
      }
    }
    if let d = v as? [String: Any] { return d.mapValues(without) }
    return v
  }

  private func withNotes(_ v: Any) -> Any {
    guard !notes.isEmpty, var d = v as? [String: Any], var held = d["notes"] as? [String: Any] else { return v }
    for key in ["urgent", "open", "fyi"] {
      let section = key == "open" ? "standard" : key
      let mine = notes.filter { $0["section"] as? String == section }
      held[key] = mine + (held[key] as? [Any] ?? [])
    }
    d["notes"] = held
    return d
  }

  private func withAsks(_ v: Any) -> Any {
    guard !asks.isEmpty, var d = v as? [String: Any] else { return v }
    d["asks"] = (d["asks"] as? [Any] ?? []) + asks
    return d
  }

  // Demo.json, with every time in it moved on by as long as it's been since it was recorded.
  private func loaded() -> [String: Any] {
    if let routes { return routes }
    var found: [String: Any] = [:]
    if let url = Bundle.main.url(forResource: "Demo", withExtension: "json"), let data = try? Data(contentsOf: url),
      var text = String(data: data, encoding: .utf8)
    {
      if let at = text.firstMatch(of: /"recorded_at":"([^"]+)"/).flatMap({ date(String($0.1)) }) {
        text = shifted(text, by: Date().timeIntervalSince(at))
      }
      let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
      found = json?["routes"] as? [String: Any] ?? [:]
    }
    routes = found
    return found
  }

  private func shifted(_ text: String, by seconds: TimeInterval) -> String {
    text.replacing(/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z/) { match in
      date(String(match.0)).map { iso($0.addingTimeInterval(seconds)) } ?? String(match.0)
    }
  }

  private let precise: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  private let plain = ISO8601DateFormatter()

  private func date(_ s: String) -> Date? { precise.date(from: s) ?? plain.date(from: s) }
  private func iso(_ d: Date) -> String { precise.string(from: d) }
}
