import SwiftUI

// A PR or an issue, opened: what it is, why it's here, the AI review (an issue's pre-review), what reviewers said, its
// state, its stack, a PR's diff and what happened lately; at its foot, what you do with it. Drawn at once from its row's card. A PR's rest lands from
// one GET /api/review/:id (the window's open), an issue's from GET /api/item; Store.readReview() says what each costs.
struct ItemPage: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  let id: String
  @State private var detail: ItemDetail?  // an issue's
  @State private var review: ReviewView?  // a PR's
  @State private var failed: String?
  @State private var sawIt = false
  @State private var replied: [String: String] = [:]  // answered from here: its latest comment then, so anything newer shows it again
  @State private var box: Box?
  // The commit the page showed when the box opened: what its write is pinned to, however the page redraws under it.
  @State private var boxHead: String?
  @State private var drafts: [String: String] = [:]
  @State private var diff: DiffModel?  // the review's diff, as it last landed
  @State private var drawn: (mark: String, at: Date)?  // what Store.mark() said when the review on screen was asked for
  @State private var fixAsked = false  // Make PR with fix was taken from this page: a second press would ask your agent twice
  @State private var sent: [SentWords] = []  // yours on the diff's lines, until the conversation has them
  // This phone's choice where a review has steps: the guided review, or every file ("traditional"). The window's own.
  @AppStorage("review.view") private var reading = "guided"

  // A box that writes, as a sheet.
  enum Box: Identifiable {
    case approve, comment, changes, reviewers
    case reply(Conversation)
    case line(LineSpot)

    var id: String {
      switch self {
      case .approve: "approve"
      case .comment: "comment"
      case .changes: "changes"
      case .reviewers: "reviewers"
      case .reply(let c): "reply:\(c.id)"
      case .line(let at): "line:\(at.key)"
      }
    }
  }

  private var card: Card? { store.card(id) ?? review?.card ?? detail?.card }
  private var item: ItemDetail.Item? { review?.item ?? detail?.item }
  private var ai: AiReview? { review?.ai ?? detail?.ai }
  private var aiStale: Bool { review?.aiStale ?? detail?.aiStale ?? false }
  private var generating: Bool { review?.generating ?? detail?.generating ?? false }
  private var events: [ActivityEvent] { review?.activity ?? detail?.activity ?? [] }
  private var stack: Stack? { review?.stack ?? detail?.stack }
  private var landed: Bool { review != nil || detail != nil }
  // The commit its review last drew: what Approve, Merge and Request changes are pinned to. Each read that lands moves
  // it, so a push the page redrew isn't refused as unread; one it hasn't drawn yet is refused by the desk.
  private var read: String? { store.pins[id] }
  // Open on GitHub (Review.tsx's `item.state === "open"`), whatever the desk resolved it as. Until its state lands, a
  // resolved card isn't taken for open: most are merged or closed.
  private var open: Bool { item.map { $0.state == "open" } ?? (card?.resolved == nil) }
  private var owing: [Conversation] { (review?.conversation ?? []).filter { $0.waitingOnYou == true } }
  private func answered(_ c: Conversation) -> Bool { replied[c.id] == (c.comments.last?.id ?? "") }
  private var waiting: [Conversation] { owing.filter { !answered($0) } }

  var body: some View {
    ScrollViewReader { proxy in page(proxy) }
  }

  private func page(_ proxy: ScrollViewProxy) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let card {
          header(card)
          why(card)
          if card.isPR { aiBlock(card, proxy) }
          if card.isPR { saidBlock(card) }
          if !card.isPR, let detail {
            IssuePre(detail: detail, busy: store.busy(card.id), run: { press($0, card) }, at: debugStep)
          }
          if let error = review?.filesError { Text("Couldn't load the diff: \(error)").sans(13).foregroundStyle(Theme.red) }
          if let review { ReviewState(card: card, review: review, addReviewers: adds(card) ? { box = .reviewers } : nil) }
          if let stack { stackBlock(stack) }
          if let review, let diff, !diff.list.isEmpty { diffBlock(card, review, diff, proxy) }
          activity(card)
          if !landed, failed == nil { LoadingLines() }
          if let failed { Text(failed).sans(13).foregroundStyle(Theme.red) }
        } else if let failed {
          Text(failed).sans(14).foregroundStyle(Theme.red)
        } else {
          LoadingLines()
        }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.top, 8)
      .padding(.bottom, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .openedPage()
    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    .sheet(item: $box) { box in sheet(box) }
    .task(id: store.loads) {
      // What it is comes with the lists; one on no list is asked for as a PR first.
      let kind = card?.kind
      if kind == nil, store.loads == 0 { return }
      if kind != "issue" {
        // A redraw waits for the desk's events to settle; another one meanwhile starts the wait again. Not every
        // update is one: the whole review, its diff too, comes again only when something about it may have changed.
        if let review {
          let job = review.aiJob?.state
          let busy = review.generating == true || review.reading == true || job == "queued" || job == "running" || store.asking.contains(id) || !Diff.pending(sent, in: review.conversation, me: store.me).isEmpty
          guard Store.redraws(mark: store.mark(id), drawn: drawn?.mark, busy: busy, since: Date().timeIntervalSince(drawn?.at ?? .distantPast)) else { return }
          try? await Task.sleep(for: .seconds(1))
          if Task.isCancelled { return }
        }
        let mark = store.mark(id)
        switch await store.readReview(id) {
        case .success(let r):
          review = r
          diff = model(r)
          drawn = (mark, Date())
          failed = nil
          if let c = r.card { saw(c) }
        case .failure(.refused(400, _)) where kind == nil: await readItem()
        case .failure(let e):
          drawn = nil
          fail(e)
        case nil: break
        }
      } else {
        // One read on open, as the window's (the desk may start its pre-review); a redraw waits for its events to settle.
        if detail != nil {
          try? await Task.sleep(for: .seconds(1))
          if Task.isCancelled { return }
        }
        await readItem()
      }
      #if DEBUG
        if let want = store.debugBox, let c = card, landed, want != "reply" || !waiting.isEmpty {
          store.debugBox = nil
          press(want, c)
        }
        if let diff, let to = store.debugScroll {
          store.debugScroll = nil
          try? await Task.sleep(for: .milliseconds(300))
          let at =
            switch to {
            case "thread": diff.firstThread(review?.conversation ?? []) ?? "diff"
            case "note": diff.firstNote(review?.ai?.notes ?? []) ?? "diff"
            case "said", "bugs": to
            case "guide": "step-0"
            default: to.hasPrefix("step-") ? to : "diff"
            }
          reach(at, ["thread", "note"].contains(to) ? .center : .top, proxy)
        }
        if let diff, let at = store.debugComment.flatMap(diff.spot) {
          store.debugComment = nil
          onLine(at)
        }
      #endif
    }
    // Popped, not covered by a page opened from it: the next time it's opened is an open again.
    .onDisappear { if !store.path.contains(.item(id)) { store.closeReview(id) } }
  }

  private func readItem() async {
    switch await store.fetchItem(id) {
    case .success(var d):
      #if DEBUG
        if let state = store.debugIssue { d = d.debugging(state) }
      #endif
      detail = d
      failed = nil
      saw(d.card)
    case .failure(let e): fail(e)
    case nil: break
    }
  }

  private func saw(_ c: Card) {
    if sawIt { return }
    sawIt = true
    store.seen(c)
  }

  // What's on screen stays; the desk being away is its bubble's to say.
  private func fail(_ e: APIError) {
    if !landed, e != .unreachable, e != .notDesk { failed = Words.capitalized(e.words) }
  }

  // MARK: What you do with it

  @ViewBuilder
  private var bar: some View {
    if let c = card {
      // An issue's pre-review can take the page's one call to action: Make PR with fix, or Block on a flagged one.
      let flagged = detail?.issueAi?.injection != nil && detail?.blockedAuthor != true
      let main = detail?.fixable == true && !fixAsked ? "fix" : flagged ? "block" : c.act(open: open)
      let name = main == "block" ? "Block @\(detail?.issueAi?.injection?.who ?? "")" : main.flatMap { Words.act[$0] }
      // Approve needs the desk's say and, as Merge, the commit it's pinned to; Reply needs what was said.
      let notYet =
        (main == "approve" && (read == nil || review?.cantApprove != nil)) || (main == "merge" && read == nil) || (main == "reply" && waiting.isEmpty)
      BottomBar(
        cta: name, go: main == "approve" || main == "handoff", off: store.busy(c.id) || notYet, press: { if let main { press(main, c) } }, quiet: quiet(c),
        hasMore: true
      ) { more(c, main) }
    } else {
      BottomBar()
    }
  }

  // + Add reviewers under who's asked: your open PR that's ready, unless the bar already asks (Review.tsx's sideAdding).
  private func adds(_ c: Card) -> Bool {
    c.mine && open && c.draft != true && item?.draft != true && c.inflight != true && c.cta != "reviewers"
  }

  private func quiet(_ c: Card) -> [Quiet] {
    if c.inflight == true { return [Quiet(label: "Back to desk") { _ in press("takeback", c) }] }
    return [
      c.active ? Quiet(label: "Done") { _ in act(c, "done") } : Quiet(label: "Back on the desk") { _ in act(c, "restore") },
      Quiet(label: "Snooze", options: [SnoozeOption.times + [SnoozeOption.activity], SnoozeOption.waits(c)]) { act(c, "snooze", $0) },
    ]
  }

  // Everything else, in the window's words: triage, the boxes, what the desk allows on GitHub now, the way out.
  @ViewBuilder
  private func more(_ c: Card, _ main: String?) -> some View {
    if c.inflight != true, !c.mine {
      Button(c.status == "muted" ? "Unmute" : "Mute") { act(c, c.status == "muted" ? "unmute" : "mute") }
    }
    if open, main != "comment" { Button("Comment") { box = .comment } }
    // On a draft the box marks it ready and asks them in one go, as the window's reviewers line above Ready for review.
    if open, c.isPR, c.mine, c.inflight != true, main != "reviewers" {
      Button(c.draft == true ? "Ready for review, asking reviewers" : "Add reviewers") { box = .reviewers }
    }
    if open, c.handsOff, c.mine || c.review == "approved", main != "handoff" { Button("Hand off for merge") { press("handoff", c) } }
    // Your chat with your agent, about this PR or issue. Nothing is sent until you send it there.
    if store.asksAgent, Asking.offered(c, blockedAuthor: detail?.blockedAuthor, landed: landed) {
      Button("Ask your agent") { store.openChat(ChatAbout(item: c.id)) }
    }
    // On GitHub, as the window's More: what the desk allows now, less what has its own button here or on the list.
    let writes = (c.actions ?? []).filter { $0 != main && !["draft", "ready", "reopen"].contains($0) && Words.more[$0] != nil }
    if !writes.isEmpty {
      Section("On GitHub") {
        ForEach(writes, id: \.self) { a in
          // Pinned to the commit read, so not before one is.
          Button(a == "close" && !c.isPR ? "Close issue" : Words.more[a] ?? a) { press(a, c) }
            .disabled(["request_changes", "merge"].contains(a) && c.isPR && read == nil)
        }
      }
    }
    if let url = c.url.flatMap(URL.init(string:)) {
      Divider()
      Button("Open on GitHub") { openURL(url) }
      Button("Copy GitHub link") {
        UIPasteboard.general.string = url.absoluteString
        store.flash("Copied the GitHub link to \(c.shortRef)")
      }
    }
  }

  // A press sends at once, as the window's buttons do, or opens the box its words go in.
  private func press(_ key: String, _ c: Card) {
    switch key {
    case "approve": pinned(.approve)
    case "comment": box = .comment
    case "request_changes", "changes": pinned(.changes)
    case "reviewers": box = .reviewers
    case "reply": if let first = waiting.first { box = .reply(first) }
    // Ready with nobody asked stays on the desk, and its page then offers Add reviewers; one already asked leaves it.
    case "ready": Task { if await store.ready(c), store.card(c.id)?.active != true { back() } }
    case "handoff": Task { if await store.handOff(c) { back() } }
    // An issue's pre-review: each spends your agent or changes the desk's blocklist, so only ever from a press.
    case "analyze", "trust": Task { await store.analyzeIssue(c, trust: key == "trust") }
    case "fix": Task { if await store.fixIssue(c) { fixAsked = true } }
    case "block", "unblock":
      Task {
        // Blocking mutes their items: this one may have left its list.
        let was = store.card(c.id)
        if await store.blockAuthor(c, key == "block"), let was, store.left(was) { back() }
      }
    case "takeback": Task { if await store.backToDesk(c) { back() } }
    default:
      Task {
        if await store.github(c, key), ["close", "merge", "unrequest"].contains(key) { back() }
      }
    }
  }

  // Approve and Request changes send the commit that was on screen when their box opened. The page reads on under the
  // sheet, so a push that lands meanwhile is refused (409) and stays refused until the box is opened again on what it drew.
  private func pinned(_ b: Box) {
    boxHead = read
    box = b
  }

  // A line's box holds the commit its line was picked at, as the window's (Review.tsx: `head: v.diff_head` when picked):
  // a push read under the sheet renumbers the lines, and the comment is for the one quoted in the box.
  private func onLine(_ at: LineSpot) {
    boxHead = review?.diffHead
    box = .line(at)
  }

  // What the desk took and took off the list goes back to the list, where its toast is.
  private func leave(_ took: Bool) -> Bool {
    if took { back() }
    return took
  }

  // Back to the list, if this page is still the one on top.
  private func back() {
    if store.path.last == .item(id) { store.path.removeLast() }
  }

  @ViewBuilder
  private func sheet(_ box: Box) -> some View {
    if let c = card {
      let draft = Binding { drafts[box.id] ?? "" } set: { drafts[box.id] = $0 }
      switch box {
      case .approve:
        WriteSheet(title: "Approve \(c.shortRef)", prompt: "A comment, if you like", button: "Approve", optional: true, go: true, draft: draft) { words in
          leave(await store.approve(c, head: boxHead ?? "", body: words.isEmpty ? nil : words))
        }
      case .comment:
        WriteSheet(title: "Comment on \(c.shortRef)", prompt: "Your comment", button: "Comment", draft: draft) { leave(await store.comment(c, body: $0)) }
      case .changes:
        WriteSheet(title: "Request changes on \(c.shortRef)", prompt: "What needs to change", button: "Request changes", draft: draft) {
          leave(await store.github(c, "request_changes", head: boxHead ?? "", body: $0))
        }
      case .reviewers:
        ReviewersSheet(card: c, keep: c.cta != "reviewers" && c.draft != true) { back() }
      case .reply(let conversation):
        WriteSheet(title: Words.replyTo("Reply", conversation, me: store.me), prompt: "Your reply", button: "Reply", draft: draft) { words in
          let was = store.card(c.id)
          let took = await store.reply(c, to: conversation, body: words)
          if took {
            replied[conversation.id] = conversation.comments.last?.id ?? ""
            // Your words show in its conversation until the review read again has them.
            sent.append(SentWords(thread: conversation.id, body: words))
            // The page stays, unless that was all it asked of you and the desk took it off.
            if let was, store.left(was) { back() }
          }
          return took
        } above: {
          VStack(alignment: .leading, spacing: 8) {
            Text(Words.place(conversation)).sans(12.5).foregroundStyle(Theme.pencil).lineLimit(1).truncationMode(.head)
            SaidComments(comments: Array(conversation.comments.suffix(3)), lines: 8)
          }
          .ruled()
        }
      case .line(let at):
        WriteSheet(title: "Comment on \(at.name)", prompt: "Your comment", button: "Comment", aside: askLine(c, at), draft: draft) { words in
          // Pinned to the commit the line was picked at, so it is the one that was read.
          let took = await store.inline(c, at: at, body: words, head: boxHead ?? "")
          if took { sent.append(SentWords(spot: at, body: words)) }
          return took
        } above: {
          Text(at.text.isEmpty ? " " : at.text).mono(12).foregroundStyle(Theme.ink).lineLimit(3)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(at.side == "old" ? Theme.delWash : Theme.wash, in: RoundedRectangle(cornerRadius: 6))
        }
      }
    }
  }

  // MARK: Ask your agent

  // About one conversation: its thread goes with the ask. None with your agent off.
  private func asking(_ c: Card) -> ((Conversation) -> Void)? {
    store.asksAgent ? { store.openChat(ChatAbout.thread(c.id, $0)) } : nil
  }

  // About one line of the diff, at the commit it was picked at, as the window's box sends it (spotOf() in Review.tsx).
  private func askLine(_ c: Card, _ at: LineSpot) -> (label: String, press: () -> Void)? {
    guard store.asksAgent, let head = boxHead, head.count == 40 else { return nil }
    return ("Ask your agent", { store.openChat(ChatAbout(item: c.id, lines: .init(path: at.path, line: at.line, side: at.side, head: head))) })
  }

  // MARK: What reviewers said

  // Each conversation waiting on you, then the rest under one line. Reply is for an open PR; the bar's answers the first.
  @ViewBuilder
  private func saidBlock(_ c: Card) -> some View {
    if let error = review?.conversationError {
      Text("Couldn't load what reviewers said: \(error)").sans(13).foregroundStyle(Theme.red)
    } else if let review {
      if !review.conversation.isEmpty {
        WhatWasSaid(
          review: review, waiting: waiting, answered: owing.filter(answered), sent: Diff.pending(sent, in: review.conversation, me: store.me),
          reply: item?.state == "open" ? { box = .reply($0) } : nil, ask: asking(c)
        )
        .id("said")
      }
    } else if c.cta == "reply", failed == nil {
      LoadingLines()
    }
  }

  // MARK: Header

  @ViewBuilder
  private func header(_ c: Card) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      // Its ref with the lines changed at the right; where they'd squeeze the repo's name (large text), under it.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          ref(c).fixedSize()
          Spacer(minLength: 8)
          changed
        }
        VStack(alignment: .leading, spacing: 4) {
          ref(c)
          changed
        }
      }
      // A title this large stops growing where a long word would no longer fit on a line.
      Text(c.title).sans(22, 650, tracking: -0.015).foregroundStyle(Theme.ink).lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      Dotted(parts: facts(c)).sans(13, tabular: true)
      if let list = review?.reviewers?.list { HeadReviewers(list: list) }
    }
  }

  private func ref(_ c: Card) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(c.repo).sans(13, tracking: -0.005).foregroundStyle(Theme.pencil).lineLimit(1).truncationMode(.middle)
      Text("#\(String(c.number))").sans(13, 550, tabular: true, tracking: -0.005).foregroundStyle(Theme.ink2).fixedSize()
      if let s = c.stack, let pos = s.pos, let size = s.size {
        Text("\(pos)/\(size)").sans(13, tabular: true).foregroundStyle(Theme.pencil).fixedSize().padding(.leading, 6)
          .accessibilityLabel("\(pos) of \(size) open PRs in its stack")
      }
    }
  }

  @ViewBuilder
  private var changed: some View {
    if card?.isPR == true, let item, (item.additions ?? 0) + (item.deletions ?? 0) > 0 {
      (Text("+\(item.additions ?? 0)").foregroundStyle(Theme.green) + Text("  \u{2212}\(item.deletions ?? 0)").foregroundStyle(Theme.red))
        .sans(13, 550, tabular: true).fixedSize()
    }
  }

  // Who it's from, a PR's stage, and how long it has waited: the row's own facts.
  private func facts(_ c: Card) -> [Dotted.Part] {
    var out: [Dotted.Part] = []
    if c.mine {
      let through = c.authorBot == true ? ", through \(c.author ?? "")" : ""
      out.append(.init("by you\(through)", Theme.ink2))
    } else {
      // Their picture before the name, as the window's head; a bot has none.
      out.append(.init("\(c.author ?? c.by ?? "")\(c.authorBot == true ? " (bot)" : "")", lead: "by", face: c.authorBot == true ? nil : c.author ?? c.by))
    }
    // Amber only on yours, where it's work for you; in Merging your agent has it, so it stays pencil.
    if let stage = c.stage {
      out.append(.init(stage, stage == "changes requested" && c.mine && c.inflight != true ? Theme.amber : Theme.pencil))
    }
    out.append(.init(Words.age(c.resolvedAt ?? c.doneAt ?? c.waitingSince, now: store.now)))
    // An issue's row doesn't say how you were asked; its why may.
    if let me = detail?.signals?.me, !Words.says(c.why ?? "", Words.asked(me)) { out.append(.init(Words.asked(me))) }
    if let n = item?.commentsTotal, n > 0 { out.append(.init(Words.plural(n, "comment"))) }
    if !c.isPR, let by = Words.placedBy(c.placedBy, agent: store.agent), !Words.says(c.why ?? "", by) { out.append(.init(by)) }
    return out
  }

  // MARK: Why it's here

  @ViewBuilder
  private func why(_ c: Card) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let resolved = c.resolved {
        Lead(label: "Resolved:", text: "\(resolved). It comes back on its own if that stops being true.")
      } else if let why = c.why, !why.isEmpty, c.inflight != true {
        Prose(text: Words.capitalized(why), size: 15, weight: 550).foregroundStyle(Theme.ink)
      }
      if let h = c.handoff {
        Lead(label: (h.from ?? "").isEmpty ? "Handed to you:" : "From \(h.from!):", text: h.why ?? "", size: 14)
      }
      if c.inflight == true, c.resolved == nil { Dotted(parts: mergingParts(c)).sans(13) }
      // Why Approve is off, in the desk's words ("you approved this commit"), as its button's tooltip in the window.
      if open, c.act(open: open) == "approve", let no = review?.cantApprove { Text(no).sans(13).foregroundStyle(Theme.pencil) }
      if !c.active, c.resolved == nil {
        Text(Words.capitalized(Words.clearedText(c, now: store.now)) + ".").sans(13).foregroundStyle(Theme.pencil)
      }
      if let labels = item?.labels, !labels.isEmpty { Text(labels.joined(separator: ", ")).sans(13).foregroundStyle(Theme.pencil) }
    }
  }

  // In Merging: what it waits on, and your agent's latest note.
  private func mergingParts(_ c: Card) -> [Dotted.Part] {
    let row = store.merging(c.id)
    var parts: [Dotted.Part] = [.init("In Merging"), .init(row?.waitsOn ?? "your agent has it")]
    if let note = row?.note?.text { parts.append(.init(note)) }
    return parts
  }

  // MARK: The AI review

  // The AI review's concerns are its first notes: each a potential bug, marked on its line. Not an earlier commit's.
  private func bugs(_ r: ReviewView) -> Int { r.aiStale == true ? 0 : r.ai?.concerns?.count ?? 0 }

  private func model(_ r: ReviewView) -> DiffModel? {
    r.order.map { DiffModel($0, guided: reading != "traditional", bugs: bugs(r)) }
  }

  @ViewBuilder
  private func aiBlock(_ c: Card, _ proxy: ScrollViewProxy) -> some View {
    // Yours gets no AI review unless asked for, so its description's first paragraph says what it's about.
    if c.mine, ai == nil, let first = item?.body?.split(whereSeparator: \.isNewline).first, !first.isEmpty {
      Prose(text: String(first), size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3)
    }
    if let review {
      let busy = review.generating == true || store.asking.contains(c.id)
      if !c.mine || review.ai != nil || busy || review.aiError != nil {
        AiSection(
          ai: review.ai, stale: review.aiStale == true, busy: busy, error: review.aiError, job: review.aiJob, now: store.now,
          open: (item?.state ?? "open") == "open", notes: review.order?.notes?.count ?? 0, agent: store.agent,
          // None for a PR in Merging: it's your agent's.
          ask: c.inflight == true ? nil : { store.askReview(c, review) },
          toLine: { path, side, line in
            if let at = diff?.place(path: path, line: line, side: side) { reach(at, .center, proxy) }
          },
          more: debugAiOpen
        )
        .padding(.top, 2)
      }
    }
  }

  private var debugStep: Int {
    #if DEBUG
      (store.debugStep ?? 1) - 1
    #else
      0
    #endif
  }

  private var debugAiOpen: Bool {
    #if DEBUG
      store.debugAi == "open"
    #else
      false
    #endif
  }

  // MARK: Its diff

  // Every file's lines in the PR's order. On an open PR a line is pressed to comment on it; a closed one only reads.
  private func diffBlock(_ c: Card, _ review: ReviewView, _ diff: DiffModel, _ proxy: ScrollViewProxy) -> some View {
    let can = item?.state == "open" && review.diffHead != nil
    return VStack(alignment: .leading, spacing: 6) {
      SmallHead(text: Words.plural(review.files.isEmpty ? diff.list.count : review.files.count, "file") + " changed").id("diff")
      // A review with steps reads two ways; the choice is this phone's and stays.
      if !(review.order?.steps ?? []).isEmpty {
        HStack(spacing: 20) {
          tab("Guided Review", on: diff.guiding) { read("guided", review, proxy) }
          tab("Traditional", on: !diff.guiding) { read("traditional", review, proxy) }
        }
      }
      DiffView(
        model: diff, files: review.files, conversation: review.conversation,
        sent: Diff.pending(sent, in: review.conversation, me: store.me), github: c.url.flatMap { URL(string: $0 + "/files") },
        comment: can ? { onLine($0) } : nil, reply: can ? { box = .reply($0) } : nil, ask: asking(c),
        notes: review.ai?.notes ?? [], looks: review.aiStale == true ? [] : review.ai?.look ?? [], bugs: bugs(review),
        diagrams: review.ai?.diagrams ?? [],
        show: { proxy.scrollTo($0) }, jump: { reach($0, .top, proxy) },
        traditional: { read("traditional", review, proxy) }
      )
      // Edge to edge: a line's wash runs the page's width, its text keeps the gutter.
      .padding(.horizontal, -Theme.pad)
    }
  }

  // One of the diff's two orders, as a word: the one on is ink with a rule under it. No box.
  private func tab(_ name: String, on: Bool, _ press: @escaping () -> Void) -> some View {
    Button(action: press) {
      Text(name).sans(14, 600).foregroundStyle(on ? Theme.ink : Theme.pencil)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { (on ? Theme.ink : Color.clear).frame(height: 2).clipShape(Capsule()) }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  // To a place far down the diff. Its lines are drawn as they come near, so the first go lands where the list guessed
  // the place would be; once that's drawn, the next lands on it. Never animated: a glide stops at the guess.
  private func reach(_ at: String, _ anchor: UnitPoint, _ proxy: ScrollViewProxy) {
    proxy.scrollTo(at, anchor: anchor)
    Task {
      for wait in [60, 200] {
        try? await Task.sleep(for: .milliseconds(wait))
        proxy.scrollTo(at, anchor: anchor)
      }
    }
  }

  // The other order, from its top.
  private func read(_ how: String, _ review: ReviewView, _ proxy: ScrollViewProxy) {
    guard reading != how || diff?.guiding != (how == "guided") else { return }
    reading = how
    diff = model(review)
    proxy.scrollTo("diff", anchor: .top)
  }

  // MARK: Its stack

  @ViewBuilder
  private func stackBlock(_ stack: Stack) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SmallHead(text: "Stack on \(stack.base ?? "its base")")
      ForEach(stack.line) { m in
        let on = m.id == id
        Button {
          if !on { store.path.append(.item(m.id)) }
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(m.state == "merged" ? "●" : m.state == "closed" ? "×" : "○").font(.system(size: 9)).foregroundStyle(Theme.pencil)
              .frame(width: 12)
            Text("#\(String(m.number ?? 0))").sans(13, on ? 600 : 400, tabular: true).foregroundStyle(on ? Theme.ink : Theme.pencil)
              .fixedSize()
            Text(m.title ?? "").sans(13, on ? 600 : 400).foregroundStyle(on ? Theme.ink : Theme.ink2).lineLimit(1)
            Spacer(minLength: 6)
            // Only what's news.
            if m.state == "open" {
              if m.ci == "red" { Text("failing").sans(13).foregroundStyle(Theme.red).fixedSize() }
              if m.review == "changes_requested" { Text("changes").sans(13).foregroundStyle(Theme.amber).fixedSize() }
              if m.review == "approved" { Text("✓").font(.system(size: 12)).foregroundStyle(Theme.green) }
            }
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
  }

  // MARK: Recent activity

  @ViewBuilder
  private func activity(_ c: Card) -> some View {
    // Less the desk's own "first seen" and what the why already says ("assigned to you").
    let events = self.events.filter { $0.kind != "new" && !Words.says(c.why ?? "", Words.eventText($0, me: store.me)) }
    if !events.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        SmallHead(text: "Recent activity")
        ForEach(events) { e in
          Dotted(parts: [.init(Words.eventText(e, me: store.me), Theme.ink2), .init(Words.age(e.at, now: store.now))])
            .sans(13, tabular: true)
        }
      }
    }
  }

  // What takes it off its list goes back to the list, where the toast offers Undo; anything else stays on its page.
  private func act(_ c: Card, _ action: String, _ snooze: SnoozeOption? = nil) {
    let leaves = store.leaves(c.id, action)
    store.act(c.id, name: c.shortRef, action, snooze: snooze)
    if leaves { back() }
  }
}

// MARK: Small pieces an opened page shares

// Parts of one line with a dot between them. A part that doesn't fit goes whole to the next line, and no dot is drawn
// where the line breaks: none dangles at a line's end or start, and no fact is split in two.
struct Dotted: View {
  struct Part {
    let text: String
    var color: Color = Theme.pencil
    var lead: String?  // "by", "reviewers": pencil words before the picture
    var face: String?  // whose picture goes before the text
    var strong: CGFloat?  // a name: this size at 550
    var mark: Text?  // after the text: a reviewer's tick
    init(_ text: String, _ color: Color = Theme.pencil, lead: String? = nil, face: String? = nil, strong: CGFloat? = nil, mark: Text? = nil) {
      self.text = text
      self.color = color
      self.lead = lead
      self.face = face
      self.strong = strong
      self.mark = mark
    }
  }

  let parts: [Part]

  var body: some View {
    DotFlow {
      ForEach(Array(parts.filter { !$0.text.isEmpty }.enumerated()), id: \.offset) { i, p in
        if i > 0 { Text("·").foregroundStyle(Theme.faint).accessibilityHidden(true) }
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          if let lead = p.lead { Text(lead + " ").foregroundStyle(Theme.pencil).fixedSize() }
          if let face = p.face { Avatar(login: face, size: p.strong.map { $0 + 1 } ?? 14) }
          let words = (Text(p.text).foregroundStyle(p.color) + (p.mark ?? Text(""))).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
          if let size = p.strong { words.sans(size, 550) } else { words }
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// Dotted's line: parts and the dots between them (every second subview is a dot), each part whole on its line.
struct DotFlow: Layout {
  var gap: CGFloat = 6  // either side of a dot
  var leading: CGFloat = 3  // between lines

  // Where each subview goes; nil for a dot at a line's break.
  private func frames(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect?], size: CGSize) {
    var out = [CGRect?](repeating: nil, count: subviews.count)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var tall: CGFloat = 0
    var wide: CGFloat = 0
    for i in stride(from: 0, to: subviews.count, by: 2) {
      let size = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
      let dot = i > 0 ? subviews[i - 1].sizeThatFits(.unspecified) : .zero
      if i > 0, x + gap + dot.width + gap + size.width <= width {
        out[i - 1] = CGRect(origin: CGPoint(x: x + gap, y: y), size: dot)
        x += gap + dot.width + gap
      } else if i > 0 {
        y += tall + leading
        x = 0
        tall = 0
      }
      out[i] = CGRect(origin: CGPoint(x: x, y: y), size: size)
      x += size.width
      tall = max(tall, size.height)
      wide = max(wide, x)
    }
    return (out, CGSize(width: wide, height: y + tall))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    frames(subviews, width: proposal.width ?? .infinity).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (i, frame) in frames(subviews, width: bounds.width).frames.enumerated() {
      if let frame {
        subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
      } else {
        // A dot at a break: off the page.
        subviews[i].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: .zero)
      }
    }
  }
}

// A bold label, then its words, as one paragraph: "Since your review: …".
struct Lead: View {
  let label: String
  let text: String
  var size: CGFloat = 13
  var labelColor = Theme.ink
  var color = Theme.ink2
  @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 100

  var body: some View {
    let s = size * scale / 100
    var head = AttributedString(label + " ")
    head.font = Font(Typeface.sans.font(s, weight: 600))
    head.foregroundColor = labelColor
    var rest = Prose.attributed(text, size: s, weight: 400, links: false)
    rest.foregroundColor = color
    return Text(head + rest).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
  }
}

struct SmallHead: View {
  let text: String
  var body: some View {
    Text(text).sans(12.5, 550).foregroundStyle(Theme.pencil).padding(.bottom, 2)
  }
}

// The risk, as the window draws it: three steps, as many lit as it's risky, then the word, in its colour.
struct RiskMeter: View {
  let risk: String

  var body: some View {
    let lit = risk == "high" ? 3 : risk == "medium" ? 2 : 1
    let color = risk == "high" ? Theme.red : risk == "medium" ? Theme.amber : Theme.green
    HStack(alignment: .center, spacing: 6) {
      HStack(spacing: 2) {
        ForEach(0..<3, id: \.self) { i in
          RoundedRectangle(cornerRadius: 1).fill(color.opacity(i < lit ? 1 : 0.25)).frame(width: 4, height: 11)
        }
      }
      .accessibilityHidden(true)
      Text("\(risk) risk").sans(13, risk == "low" ? 500 : 600).foregroundStyle(color)
    }
    .fixedSize()
  }
}

// A plain button: a hairline edge on the sheet, as the window's.
struct PlainAct: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .sans(13, 500)
      .foregroundStyle(Theme.ink)
      .padding(.horizontal, 10)
      .frame(minHeight: 36)
      .background(configuration.isPressed ? Theme.wash : Theme.sheet, in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.ruleStrong, lineWidth: 1))
      .contentShape(Rectangle().inset(by: -4))
  }
}

// Things on a line that wrap onto the next when they run out of room.
struct FlowLine: Layout {
  var spacing: CGFloat = 8

  private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
    var rows: [[(Int, CGSize)]] = [[]]
    var x: CGFloat = 0
    for (i, v) in subviews.enumerated() {
      let size = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
      if x > 0, x + size.width > width {
        rows.append([])
        x = 0
      }
      rows[rows.count - 1].append((i, size))
      x += size.width + spacing
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var height: CGFloat = 0
    var widest: CGFloat = 0
    for row in rows(subviews, width: width) {
      height += (row.map(\.1.height).max() ?? 0) + (height > 0 ? spacing : 0)
      let across: CGFloat = row.map(\.1.width).reduce(0, +) + CGFloat(max(0, row.count - 1)) * spacing
      widest = max(widest, across)
    }
    return CGSize(width: min(width, widest), height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(subviews, width: bounds.width) {
      let height = row.map(\.1.height).max() ?? 0
      var x = bounds.minX
      for (i, size) in row {
        subviews[i].place(
          at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
        x += size.width + spacing
      }
      y += height + spacing
    }
  }
}

// Text on its way: a few calm bars.
struct LoadingLines: View {
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach([0.9, 0.75, 0.5], id: \.self) { w in
        RoundedRectangle(cornerRadius: 4).fill(Theme.wash).frame(height: 10).frame(maxWidth: .infinity, alignment: .leading)
          .scaleEffect(x: w, anchor: .leading)
      }
    }
    .opacity(shown ? 1 : 0)
    .task {
      try? await Task.sleep(for: .milliseconds(150))
      withAnimation(.easeOut(duration: 0.2)) { shown = true }
    }
    .accessibilityHidden(true)
  }
}
