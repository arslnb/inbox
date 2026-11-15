import Foundation
import Observation
import SwiftUI
import UIKit

enum Page: String, CaseIterable, Sendable {
  case inbox, blocked, merging, archive

  var name: String {
    switch self {
    case .inbox: "Inbox"
    case .blocked: "Blocked"
    case .merging: "Merging"
    case .archive: "Archive"
    }
  }
}

enum Route: Hashable, Sendable {
  case item(String)
  case inquiry(String)
  case session(String)
}

struct Toast: Equatable {
  let id = UUID()
  let text: String
  var undo: Int?  // the action's undo_seq, while Undo is offered
  var revert: Revert?  // a GitHub write Undo takes back with another: a closed PR reopened, a draft made ready again

  struct Revert: Equatable {
    let id: String
    let to: String  // "reopen" | "ready"
  }

  var undoable: Bool { undo != nil || revert != nil }
}

// Everything the views draw from: which desk, what it last said, and what you just did. The desk decides what's on each
// list and in what order; this only keeps the last answer (in memory: nothing is cached on disk) and renders it.
@MainActor
@Observable
final class Store {
  // The desk this phone is connected to; nil shows the connect screen.
  private(set) var address: DeskAddress?
  private(set) var deviceName: String?
  var connectNote: String?  // why the connect screen is back (the device was revoked)

  var page: Page = .inbox
  var path: [Route] = []
  var showSettings = false
  var snoozing: Card?  // the row whose Snooze was swiped: its options are asked for

  private(set) var overview: Overview?
  private(set) var queue: QueueView?
  private(set) var inflight: InflightView?
  private(set) var loads = 0  // bumped on every answer from the desk: an opened item refetches
  private(set) var offline = false
  private(set) var starting: String?
  private(set) var broken: String?
  private(set) var refused: String?  // the desk's words for a read it wouldn't give (another Tailscale login, a desk this app can't read)
  private(set) var leaving: Set<String> = []
  private(set) var sending: Set<String> = []  // what has a write on its way: an item's, question's or session's id
  private(set) var pins: [String: String] = [:]  // an opened PR's commit, as its review last drew it: what Approve and Merge send
  private(set) var toast: Toast?
  private(set) var failures: [Notice] = []
  private(set) var deskVersion: String?
  var dismissed: [String: String] = [:]
  var folded: Set<String> = ["cleared", "hidden"]  // the Archive's two quiet groups start closed
  var now = Date()

  @ObservationIgnored private var client: APIClient?
  @ObservationIgnored private var live: Task<Void, Never>?
  @ObservationIgnored private var pending: Task<Void, Never>?
  @ObservationIgnored private var toastTimer: Task<Void, Never>?
  @ObservationIgnored private var reviewsOpen: Set<String> = []  // the PRs whose page has had its opening read
  @ObservationIgnored private var session: URLSession
  @ObservationIgnored var debugEmpty = false  // DEBUG shots: draw the desk as if nothing were on it
  @ObservationIgnored private let defaults: UserDefaults

  private static let addressKey = "desk.address"
  private static let deviceKey = "desk.device"
  private static let phoneKey = "desk.phone"  // paired as a phone: an older pairing's token is a machine's, refused every write

  init(defaults: UserDefaults = .standard, session: URLSession = APIClient.plain) {
    self.defaults = defaults
    self.session = session
    if let saved = defaults.string(forKey: Store.addressKey), case .success(let parsed) = DeskAddress.parse(saved) {
      let token = Keychain.read(for: parsed.address.text)
      if !parsed.address.isLocal, token != nil, !defaults.bool(forKey: Store.phoneKey) {
        Keychain.delete(for: parsed.address.text)
        lastAddress = parsed.address.text
        connectNote =
          "This phone was paired before it could act for you. Pair it again: Pair a device, in Settings → Network on the desk's computer, shows a code. Its old pairing can be revoked there, in Settings → Network."
      } else if parsed.address.isLocal || token != nil {
        // A tailnet address without its token can't ask anything: back to pairing.
        address = parsed.address
        deviceName = defaults.string(forKey: Store.deviceKey)
        client = APIClient(address: parsed.address, token: token, session: session)
      }
    }
  }

  var agent: String { overview?.aiAgent ?? "Claude" }
  var me: String { overview?.me ?? "" }
  var inboxCount: Int { queue.map { Lists.inboxCount($0, leaving: leaving) } ?? 0 }

  // MARK: Connecting

  // Returns the words to show when it didn't work. A code is traded once per press, never retried here.
  func connect(typed: String, code typedCode: String) async -> String? {
    let parsed: (address: DeskAddress, code: String?)
    switch DeskAddress.parse(typed) {
    case .failure(let why): return why.words
    case .success(let p): parsed = p
    }
    let address = parsed.address
    var fresh = APIClient(address: address, token: nil, session: session)
    var device: String?
    do {
      if address.isLocal {
        // The desk's own computer: no code, no token. Just see that a desk answers.
        deskVersion = try await fresh.health().version
      } else {
        // A pasted pairing link's code wins: whatever was typed before it is a code already tried, and any try burns the new one.
        guard let code = parsed.code ?? PairingCode.normalize(typedCode) else {
          return "A pairing code is 8 letters and digits, like ABCD-2345: Pair a device shows one, in Settings → Network on the desk's computer."
        }
        let answer = try await fresh.pair(code: code, name: UIDevice.current.name)
        guard let token = answer.token, !token.isEmpty else { return "The desk paired this device but sent no token." }
        guard Keychain.save(token, for: address.text) else { return "Couldn't keep the token in this phone's Keychain." }
        fresh.token = token
        device = answer.device?.name
      }
    } catch let e as APIError {
      return address.isLocal ? Store.localWords(e, address) : PairFailure(e, host: address.host).words
    } catch {
      return nil  // cancelled
    }
    defaults.set(address.text, forKey: Store.addressKey)
    defaults.set(device, forKey: Store.deviceKey)
    defaults.set(!address.isLocal, forKey: Store.phoneKey)
    adopt(address, device: device, client: fresh)
    return nil
  }

  private static func localWords(_ e: APIError, _ address: DeskAddress) -> String {
    switch e {
    case .unreachable: "Nothing answers at \(address.text). Start the desk with desk serve, or open the desktop app."
    case .notDesk: "Something answers at \(address.text), but it isn't the desk."
    default: Words.capitalized(e.words) + "."
    }
  }

  private func adopt(_ address: DeskAddress, device: String?, client: APIClient) {
    self.address = address
    deviceName = device
    self.client = client
    connectNote = nil
    reset()
    startLive()
  }

  private func reset() {
    overview = nil
    queue = nil
    inflight = nil
    offline = false
    starting = nil
    broken = nil
    refused = nil
    leaving = []
    sending = []
    toast = nil
    failures = []
    dismissed = [:]
    reviewsOpen = []
    pins = [:]
    path = []
    page = .inbox
    showSettings = false
  }

  // Forgets the token on this phone. The device stays listed on the desk until its owner revokes it there.
  func disconnect(note: String? = nil) {
    stopLive()
    if let address { Keychain.delete(for: address.text) }
    defaults.removeObject(forKey: Store.deviceKey)
    defaults.removeObject(forKey: Store.phoneKey)
    if note == nil { defaults.removeObject(forKey: Store.addressKey) }
    lastAddress = note == nil ? "" : (address?.text ?? "")
    address = nil
    client = nil
    deviceName = nil
    reset()
    connectNote = note
  }

  private(set) var lastAddress = ""  // the connect screen's address, after a revoke

  // MARK: Loading

  func load() async {
    guard let client else { return }
    do {
      async let o = client.overview()
      async let q = client.queue()
      let (ov, qv) = try await (o, q)
      overview = ov
      queue = debugEmpty ? QueueView() : qv
      if page == .merging || inflight != nil { inflight = try await client.inflight() }
      offline = false
      starting = nil
      broken = nil
      refused = nil
      loads += 1
    } catch let e as APIError {
      took(e)
    } catch {}
  }

  // What a failed read means for the page: only an answer the desk itself gave is shown as its words.
  private func took(_ e: APIError, action: Bool = false) {
    switch e {
    case .unreachable, .notDesk:
      offline = true
      starting = nil
      refused = nil
    case .unpaired:
      disconnect(note: "This phone isn't paired with the desk any more: it was revoked on the desk's computer. Pair it again.")
    case .starting(let m):
      offline = false
      starting = m
      refused = nil
    case .rules(let m):
      offline = false
      starting = nil
      refused = nil
      broken = m
    case .refused(_, let m):
      offline = false
      starting = nil
      // An action's refusal fades; a read's stays until the desk answers one.
      if action { fail(m) } else { refused = m }
    }
  }

  func openMerging() async {
    guard let client, inflight == nil else { return }
    do { inflight = try await client.inflight() } catch let e as APIError { took(e) } catch {}
  }

  // Pull to refresh: asks the desk to sync now, then reads what it has. The sync's own result arrives as an update.
  func refresh() async {
    guard let client else { return }
    // A sync nothing answered already says the desk is away: no second wait for the read to say it again.
    do { try await client.sync() } catch let e as APIError {
      if e == .unreachable || e == .notDesk { return took(e) }
    } catch {}
    await load()
  }

  func retry() {
    Task { await load() }
  }

  func syncNow() {
    Task { await refresh() }
  }

  // MARK: Live

  // The desk's event stream while the app is in front: every update refetches, debounced as the window's (they come in
  // bursts during a sync). A stream that ends or never opens reads once and tries again, a little later each time.
  func startLive() {
    stopLive()
    guard let client else { return }
    live = Task { [weak self] in
      if Task.isCancelled { return }
      // Read first: a desk that doesn't answer (its computer asleep) holds the stream's request for a minute before it fails.
      await self?.load()
      var wait = 1.0
      while !Task.isCancelled {
        do {
          for try await _ in client.events() {
            wait = 1
            self?.loadSoon()
          }
        } catch {}
        if Task.isCancelled { return }
        await self?.load()
        try? await Task.sleep(for: .seconds(wait))
        wait = min(wait * 2, 15)
      }
    }
  }

  func stopLive() {
    live?.cancel()
    live = nil
    pending?.cancel()
    pending = nil
  }

  private func loadSoon() {
    pending?.cancel()
    pending = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      if Task.isCancelled { return }
      await self?.load()
    }
  }

  // MARK: Acting

  // Whether an action takes the row off its list, as the window has it: Done, Snooze and Mute do, to an active item.
  // A resolved one stays under the Archive whatever you do to it, and so does one already snoozed or muted.
  func leaves(_ id: String, _ action: String) -> Bool {
    guard ["done", "snooze", "mute"].contains(action) else { return false }
    guard let c = card(id) else { return true }  // a session
    return c.active && c.resolved == nil
  }

  // done, snooze, mute, unmute, restore: triage, with the desk's own Undo. The row leaves at once, and comes back if the desk refuses.
  func act(_ id: String, name: String, _ action: String, snooze: SnoozeOption? = nil) {
    guard let client else { return }
    let leaves = leaves(id, action)
    if leaves { withAnimation(.easeOut(duration: 0.2)) { _ = leaving.insert(id) } }
    Task {
      do {
        let answer = try await client.act(id, action, until: snooze?.until)
        let verbs = ["done": "Done", "mute": "Muted", "unmute": "Unmuted", "restore": "Restored"]
        let verb = snooze.map { "Snoozed \($0.toast)" } ?? verbs[action] ?? Words.capitalized(action)
        flash("\(verb): \(name)", undo: (answer.undoSeq ?? 0) > 0 ? answer.undoSeq : nil)
        await load()
      } catch let e as APIError {
        took(e, action: true)
      } catch {}
      leaving.remove(id)
    }
  }

  // MARK: Writing (a paired phone is your hands, like the desk's window)
  //
  // Each of these sends one write and answers whether the desk took it, so a page can keep a draft that wasn't sent:
  //   Task { if await store.comment(card, body: draft) { draft = "" } }
  // While it's on its way `busy(id)` is true and a second press sends nothing. A success shows the window's toast and
  // reads the desk again; a refusal (403, 409, 5xx) shows the desk's own words in a bubble. Nothing asks twice.

  func busy(_ id: String) -> Bool { sending.contains(id) }

  // Why the last write wasn't taken, for a sheet to say (it covers the bubbles): the desk's own words where it gave any.
  private(set) var whyNot: String?

  // `leaves`: the row goes at once, as in the window, and is back if the desk refuses.
  private func write(
    _ id: String, leaves: Bool = false, still: String = "Something else is still on its way for it: try again in a moment.",
    _ run: (APIClient) async throws -> Toast
  ) async -> Bool {
    guard let client else { return false }
    if sending.contains(id) {
      whyNot = still
      return false
    }
    whyNot = nil
    sending.insert(id)
    if leaves { withAnimation(.easeOut(duration: 0.2)) { _ = leaving.insert(id) } }
    defer {
      sending.remove(id)
      leaving.remove(id)
    }
    do {
      let said = try await run(client)
      flash(said.text, revert: said.revert)
      await load()
      return true
    } catch let e as APIError {
      took(e, action: true)
      switch e {
      case .unreachable, .notDesk:
        // No answer isn't a no: a write that reached the desk lands whether or not its answer got back. Read what it has.
        whyNot = "The desk didn't answer, so it may or may not have been sent. Look before sending it again."
        Task { await load() }
      case .starting(let m), .rules(let m): whyNot = m
      case .refused(_, let m):
        whyNot = m
        // A refusal often means what's on screen is old (new commits, already answered): read it again.
        await load()
      case .unpaired: break
      }
      return false
    } catch { return false }
  }

  // Approve, pinned to the commit the review last drew (`pins`, set as each read lands): a push the page redrew is
  // approved, one it hasn't drawn yet is refused by the desk (409). Offered on someone else's open PR;
  // ReviewView.approve says why not. The window sends no comment with it.
  @discardableResult
  func approve(_ c: Card, head: String? = nil, body: String? = nil) async -> Bool {
    await write(c.id, leaves: true) { client in
      _ = try await client.approve(c.id, head: head ?? self.pins[c.id] ?? "", body: body)
      return Toast(text: "Approved \(c.shortRef) on GitHub")
    }
  }

  // A comment on a PR or an issue. The desk marks it done.
  @discardableResult
  func comment(_ c: Card, body: String) async -> Bool {
    await write(c.id, leaves: true) { client in
      _ = try await client.comment(c.id, body: body)
      return Toast(text: "Commented on \(c.shortRef) on GitHub")
    }
  }

  // A reply in one conversation of readReview()'s. The item leaves the desk only if this was the last one waiting on
  // you, which the next read says; read the review again to see the reply in its conversation.
  @discardableResult
  func reply(_ c: Card, to conversation: Conversation, body: String) async -> Bool {
    await write(c.id) { client in
      _ = try await client.reply(c.id, to: conversation.id, body: body)
      return Toast(text: "Sent your reply to \(conversation.comments.last?.author ?? "them")")
    }
  }

  // A comment on a line of the diff, pinned to the commit the diff was read at (ReviewView.diffHead, not the item's
  // head: they differ until the next sync). Part of reviewing, not its end: the PR stays, and so does its page. One at a
  // time per line, as the desk's own lock; another line's goes meanwhile.
  @discardableResult
  func inline(_ c: Card, at spot: LineSpot, body: String, head: String) async -> Bool {
    await write("\(c.id) \(spot.path):\(spot.line)", still: "Still sending your last comment there.") { client in
      _ = try await client.inline(c.id, at: spot, body: body, head: head)
      return Toast(text: "Commented on \(spot.name) on GitHub")
    }
  }

  // Ready for review on your draft, asking whoever was picked from fetchReviewers() (nobody: the row's own button).
  @discardableResult
  func ready(_ c: Card, asking picked: [Reviewer] = []) async -> Bool {
    let names = picked.map(\.login).joined(separator: ", ")
    return await write(c.id, leaves: true) { client in
      do {
        let r = try await client.ready(c.id, users: picked.filter { $0.team != true }.map(\.id), teams: picked.filter { $0.team == true }.map(\.id))
        let did = "Marked \(c.shortRef) ready for review\(names.isEmpty ? "" : " and asked \(names)") on GitHub"
        return Toast(text: r.done == false ? "\(did). Nobody's asked to review it yet" : did)
      } catch APIError.refused(let status, let m) where m.hasPrefix("Marked it ready") && !names.isEmpty {
        // Half done (tag ReviewersNotAsked): it is ready, the requests weren't sent, and nothing is rolled back.
        throw APIError.refused(status: status, message: "\(m). Ask \(names) on GitHub.")
      }
    }
  }

  // Ask reviewers on your ready PR. Without `keep` it leaves the desk (they have it now); `keep` adds one more and it stays.
  @discardableResult
  func askReviewers(_ c: Card, _ picked: [Reviewer], keep: Bool = false) async -> Bool {
    let names = picked.map(\.login).joined(separator: ", ")
    return await write(c.id, leaves: !keep) { client in
      try await client.askReviewers(c.id, users: picked.filter { $0.team != true }.map(\.id), teams: picked.filter { $0.team == true }.map(\.id), keep: keep)
      return Toast(text: "Asked \(names) to review \(c.shortRef) on GitHub")
    }
  }

  // The row's Merge and the More menu: one of Card.actions (Words.more names them). Merge and request_changes are pinned
  // to the commit its review last drew (request_changes needs it, and `body`: what needs to change). "ready" goes the way of ready().
  // Close, merge, request changes and unrequest take it off the desk at once; the toast's Undo reopens a closed PR and
  // makes a converted draft ready again.
  @discardableResult
  func github(_ c: Card, _ action: String, head: String? = nil, body: String? = nil) async -> Bool {
    if action == "ready" { return await ready(c) }
    return await write(c.id, leaves: ["close", "merge", "request_changes", "unrequest"].contains(action)) { client in
      _ = try await client.github(c.id, action, head: head ?? self.pins[c.id], body: body)
      let to = action == "close" && c.isPR ? "reopen" : action == "draft" ? "ready" : nil
      return Toast(text: "\(Words.did[action] ?? Words.capitalized(action)): \(c.shortRef)", revert: to.map { Toast.Revert(id: c.id, to: $0) })
    }
  }

  // Undo of a close or a draft, as the window: another write. Ready for review took it off the desk, so that is undone too.
  private func undoWrite(_ w: Toast.Revert) {
    toast = nil
    Task {
      _ = await write(w.id) { client in
        if w.to == "ready" {
          if try await client.ready(w.id).done == true { _ = try await client.act(w.id, "undo") }
        } else {
          _ = try await client.github(w.id, "reopen")
        }
        let short = w.id.replacingOccurrences(of: #"^[^/]+/"#, with: "", options: .regularExpression)
        return Toast(text: "Undid it on GitHub: \(short) is \(w.to == "ready" ? "ready for review" : "open") again")
      }
    }
  }

  // Hand off for merge: your agent gets it merged. Offer it when card.handsOff. No Undo: Back to desk is the undo.
  @discardableResult
  func handOff(_ c: Card) async -> Bool {
    await write(c.id, leaves: true) { client in
      _ = try await client.act(c.id, "inflight")
      return Toast(text: "Handed off for merge: \(c.shortRef). Your agent gets it merged.")
    }
  }

  // Back to desk, from Merging (card.inflight).
  @discardableResult
  func backToDesk(_ c: Card) async -> Bool {
    await write(c.id, leaves: true) { client in
      _ = try await client.act(c.id, "takeback")
      return Toast(text: "Back on your desk: \(c.shortRef)")
    }
  }

  // Your answer to an agent's question: one of its options' words or your own; nil dismisses it (the agent decides itself).
  // Its row leaves the Inbox at once (`leaving` has its id). Answering the coordinator wakes it, as in the window.
  @discardableResult
  func answer(_ q: Inquiry, text: String?) async -> Bool {
    await write(q.id, leaves: true) { client in
      _ = try await client.answer(q.id, text: text)
      return Toast(text: text == nil ? "Dismissed \(Words.fromName(q.from, start: false))'s question" : "Answered \(Words.fromName(q.from, start: false))")
    }
  }

  // Kick or Resume (whichever SessionCard.actions has): the session carries on in the background on the desk's computer.
  // Open and attach are for that computer and aren't offered from here.
  @discardableResult
  func kick(_ s: SessionCard) async -> Bool {
    await write(s.id) { client in
      _ = try await client.kick(s.id)
      return Toast(text: "\(s.actions?.contains("resume") == true ? "Resumed" : "Kicked") \(s.name ?? "it"): it carries on in the background.")
    }
  }

  // Opening an item is seeing it: the desk clears its "new". Nothing to show, nothing to undo.
  func seen(_ card: Card) {
    guard let client, card.new == true else { return }
    Task { _ = try? await client.act(card.id, "seen") }
  }

  func undo() {
    if let revert = toast?.revert { return undoWrite(revert) }
    guard let client, let seq = toast?.undo else { return }
    toast = nil
    Task {
      do {
        let r = try await client.undo(seq: seq)
        let short = (r.id ?? "").replacingOccurrences(of: #"^[^/]+/"#, with: "", options: .regularExpression)
        flash("Undid \(r.action ?? "that") on \(short)")
        await load()
      } catch let e as APIError {
        took(e, action: true)
      } catch {}
    }
  }

  func flash(_ text: String, undo: Int? = nil, revert: Toast.Revert? = nil) {
    toastTimer?.cancel()
    toast = Toast(text: text, undo: undo, revert: revert)
    toastTimer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { self?.toast = nil }
    }
  }

  // An action that failed: a bubble in the desk's own words, at most three, each fading on its own.
  private func fail(_ text: String) {
    let notice = Notice(id: "failed:\(Date().timeIntervalSince1970)", sig: text, tone: .red, title: text, transient: true)
    failures = Array((failures.filter { $0.title != text } + [notice]).suffix(3))
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      self?.failures.removeAll { $0.id == notice.id }
    }
  }

  func dismiss(_ n: Notice) {
    if n.transient { failures.removeAll { $0.id == n.id } } else { dismissed[n.id] = n.sig }
  }

  var notices: [Notice] {
    guard address != nil else { return [] }
    let all = Notices.of(
      Conditions(
        offline: offline, local: address?.isLocal ?? false, starting: starting, refused: refused, broken: broken, overview: overview,
        paused: queue?.paused, agent: agent), now: now)
    return all.filter { dismissed[$0.id] != $0.sig } + failures
  }

  // MARK: Finding what's on screen

  func card(_ id: String) -> Card? {
    guard let q = queue else { return inflight?.rows.first { $0.card.id == id }?.card }
    let lists = [q.inbox?.urgent, q.inbox?.standard, q.inbox?.fyi, q.sections?.blocked, q.cleared, q.resolved, q.hidden]
    return lists.compactMap { $0?.first { $0.id == id } }.first ?? inflight?.rows.first { $0.card.id == id }?.card
  }

  func merging(_ id: String) -> InflightView.Row? { inflight?.rows.first { $0.card.id == id } }

  func fetchItem(_ id: String) async -> Result<ItemDetail, APIError>? {
    guard let client else { return nil }
    do { return .success(try await client.item(id)) } catch let e as APIError {
      if case .unpaired = e { took(e) }
      return .failure(e)
    } catch { return nil }
  }

  // A PR's review, for its page. The first read of an opened PR is the window's open (the desk may start its AI review
  // and your agent's read of what waits on you); every one after it is a redraw (?ahead=1), which starts nothing, so an
  // event never restarts a failed job. Rows and lists never call this. Not for issues (400).
  func readReview(_ id: String) async -> Result<ReviewView, APIError>? {
    guard let client else { return nil }
    let ahead = reviewsOpen.contains(id)
    reviewsOpen.insert(id)  // once it's sent: a read cut short may have reached the desk
    do {
      let r = try await client.review(id, ahead: ahead)
      // Still its page: one left while this was on its way pins nothing.
      if reviewsOpen.contains(id), let head = r.item?.headOid { pins[id] = head }
      return .success(r)
    } catch let e as APIError {
      if !ahead, e == .unreachable || e == .notDesk { reviewsOpen.remove(id) }  // it never reached the desk
      if case .unpaired = e { took(e) }
      return .failure(e)
    } catch { return nil }
  }

  // Its page was left: the next time it's opened is an open again.
  func closeReview(_ id: String) {
    reviewsOpen.remove(id)
    pins[id] = nil
  }

  // Who to ask to review your PR; an empty search is GitHub's own picks.
  func fetchReviewers(_ id: String, search: String = "") async -> Result<[Reviewer], APIError>? {
    guard let client else { return nil }
    do { return .success(try await client.reviewers(id, search: search)) } catch let e as APIError {
      if case .unpaired = e { took(e) }
      return .failure(e)
    } catch { return nil }
  }

  func fetchInquiry(_ id: String) async -> Result<Inquiry, APIError>? {
    guard let client else { return nil }
    do { return .success(try await client.inquiry(id)) } catch let e as APIError {
      if case .unpaired = e { took(e) }
      return .failure(e)
    } catch { return nil }
  }

  #if DEBUG
    // Launch arguments for ios/shots.sh and for trying a state by hand; none of them is saved, and none is read in a release build.
    //   -deskURL http://localhost:47841   use this desk (localhost only), without touching the saved one
    //   -connect [-connectError "<words>"] [-connectAddress <text>]   the connect screen
    //   -page inbox|blocked|merging|archive   -open <item id>|inquiry:<id>|session:<id>   -settings   -empty
    //   -box approve|comment|changes|reviewers|reply|answer   with -open: that page's box, opened once it has loaded
    //   -part checks|reviewers   with -open: that line of a PR's State, opened
    //   -scroll diff|thread   with -open: a PR's page scrolled to its diff, or to the first thread on a line of it
    //   -comment <path>:<line>   with -open: the box for a comment on that line of the new file
    func applyLaunchArguments(_ args: UserDefaults = .standard, flags: [String] = ProcessInfo.processInfo.arguments) {
      guard flags.contains(where: { ["-deskURL", "-connect"].contains($0) }) else { return }
      stopLive()
      address = nil
      client = nil
      connectNote = args.string(forKey: "connectError")
      lastAddress = args.string(forKey: "connectAddress") ?? ""
      debugScan = args.string(forKey: "scan")
      guard !flags.contains("-connect"), let typed = args.string(forKey: "deskURL"), case .success(let parsed) = DeskAddress.parse(typed),
        parsed.address.isLocal
      else { return }
      address = parsed.address
      client = APIClient(address: parsed.address, token: nil, session: session)
      debugEmpty = flags.contains("-empty")
      page = Page(rawValue: args.string(forKey: "page") ?? "") ?? .inbox
      if let open = args.string(forKey: "open") {
        if open.hasPrefix("inquiry:") { path = [.inquiry(String(open.dropFirst(8)))] }
        else if open.hasPrefix("session:") { path = [.session(open)] }
        else { path = [.item(open)] }
      }
      showSettings = flags.contains("-settings")
      scrollTo = args.string(forKey: "scrollTo")
      debugBox = args.string(forKey: "box")
      debugPart = args.string(forKey: "part")
      debugScroll = args.string(forKey: "scroll")
      debugComment = args.string(forKey: "comment")
    }

    var scrollTo: String?
    var debugBox: String?
    var debugPart: String?
    var debugScroll: String?
    var debugComment: String?
    var debugScan: String?  // what the camera would have read: the connect screen takes it once
  #endif
}
