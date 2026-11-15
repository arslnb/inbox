import SwiftUI

// A PR or an issue, opened: what it is, why it's here, what waits on your reply, the AI review, its state, its stack,
// a PR's diff and what happened lately; at its foot, what you do with it. Drawn at once from its row's card. A PR's rest lands from
// one GET /api/review/:id (the window's open), an issue's from GET /api/item; Store.readReview() says what each costs.
struct ItemPage: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  let id: String
  @State private var detail: ItemDetail?  // an issue's
  @State private var review: ReviewView?  // a PR's
  @State private var failed: String?
  @State private var sawIt = false
  @State private var replied: Set<String> = []
  @State private var box: Box?
  @State private var drafts: [String: String] = [:]
  @State private var diff: DiffModel?  // the review's diff, as it last landed
  @State private var sent: [SentWords] = []  // yours on the diff's lines, until the conversation has them

  // A box that writes, as a sheet.
  enum Box: Identifiable {
    case approve, comment, changes, reviewers
    case reply(Conversation, onLine: Bool = false)  // onLine: from its line of the diff, where the page stays
    case line(LineSpot)

    var id: String {
      switch self {
      case .approve: "approve"
      case .comment: "comment"
      case .changes: "changes"
      case .reviewers: "reviewers"
      case .reply(let c, _): "reply:\(c.id)"
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
  private var open: Bool { card?.resolved == nil && (item?.state ?? "open") == "open" }
  private var waiting: [Conversation] { (review?.conversation ?? []).filter { $0.waitingOnYou == true && !replied.contains($0.id) } }

  var body: some View {
    ScrollViewReader { proxy in page(proxy) }
  }

  private func page(_ proxy: ScrollViewProxy) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let card {
          header(card)
          why(card)
          if card.isPR { owed(card) }
          if card.isPR { aiBlock(card) }
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
        // A redraw waits for the desk's events to settle; another one meanwhile starts the wait again.
        if review != nil {
          try? await Task.sleep(for: .seconds(1))
          if Task.isCancelled { return }
        }
        switch await store.readReview(id) {
        case .success(let r):
          review = r
          diff = r.order.map { DiffModel($0) }
          failed = nil
          if let c = r.card { saw(c) }
        case .failure(.refused(400, _)) where kind == nil: await readItem()
        case .failure(let e): fail(e)
        case nil: break
        }
      } else {
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
          proxy.scrollTo(to == "thread" ? diff.firstThread(review?.conversation ?? []) ?? "diff" : "diff", anchor: to == "thread" ? .center : .top)
        }
        if let diff, let at = store.debugComment.flatMap(diff.spot) {
          store.debugComment = nil
          box = .line(at)
        }
      #endif
    }
    // Popped, not covered by a page opened from it: the next time it's opened is an open again.
    .onDisappear { if !store.path.contains(.item(id)) { store.closeReview(id) } }
  }

  private func readItem() async {
    switch await store.fetchItem(id) {
    case .success(let d):
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
      let main = c.act(open: open)
      // Approve needs the desk's say and, as Merge, the commit it's pinned to; Reply needs what was said.
      let notYet =
        (main == "approve" && (read == nil || review?.cantApprove != nil)) || (main == "merge" && read == nil) || (main == "reply" && waiting.isEmpty)
      BottomBar(
        cta: main.flatMap { Words.act[$0] }, off: store.busy(c.id) || notYet, press: { if let main { press(main, c) } }, quiet: quiet(c),
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
    case "approve": box = .approve
    case "comment": box = .comment
    case "request_changes", "changes": box = .changes
    case "reviewers": box = .reviewers
    case "reply": if let first = waiting.first { box = .reply(first) }
    // Ready with nobody asked stays on the desk, and its page then offers Add reviewers; one already asked leaves it.
    case "ready": Task { if await store.ready(c), store.card(c.id)?.active != true { back() } }
    case "handoff": Task { if await store.handOff(c) { back() } }
    case "takeback": Task { if await store.backToDesk(c) { back() } }
    default:
      Task {
        if await store.github(c, key), ["close", "merge", "unrequest"].contains(key) { back() }
      }
    }
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
        WriteSheet(title: "Approve \(c.shortRef)", prompt: "A comment, if you like", button: "Approve", optional: true, draft: draft) { words in
          leave(await store.approve(c, body: words.isEmpty ? nil : words))
        }
      case .comment:
        WriteSheet(title: "Comment on \(c.shortRef)", prompt: "Your comment", button: "Comment", draft: draft) { leave(await store.comment(c, body: $0)) }
      case .changes:
        WriteSheet(title: "Request changes on \(c.shortRef)", prompt: "What needs to change", button: "Request changes", draft: draft) {
          leave(await store.github(c, "request_changes", body: $0))
        }
      case .reviewers:
        ReviewersSheet(card: c, keep: c.cta != "reviewers" && c.draft != true) { back() }
      case .reply(let conversation, let onLine):
        WriteSheet(title: "Reply to \(conversation.comments.last?.author ?? "them")", prompt: "Your reply", button: "Reply", draft: draft) { words in
          let took = await store.reply(c, to: conversation, body: words)
          if took { replied.insert(conversation.id) }
          // From its line of the diff the page stays, with your words under the thread until it's read again.
          if onLine {
            if took { sent.append(SentWords(thread: conversation.id, body: words)) }
            return took
          }
          // The last one answered: nothing more waits on you here.
          return took && waiting.isEmpty ? leave(true) : took
        } above: {
          said(conversation, whole: true)
        }
      case .line(let at):
        WriteSheet(title: "Comment on \(at.name)", prompt: "Your comment", button: "Comment", draft: draft) { words in
          // Pinned to the commit the diff is at, so the line is the one that was read.
          let took = await store.inline(c, at: at, body: words, head: review?.diffHead ?? "")
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

  // MARK: Waiting on your reply

  // What was said in each conversation that waits on you, briefly: where, its last words, and Reply (the bar's answers the first).
  @ViewBuilder
  private func owed(_ c: Card) -> some View {
    if let error = review?.conversationError {
      Text("Couldn't load what reviewers said: \(error)").sans(13).foregroundStyle(Theme.red)
    } else if review == nil {
      if c.cta == "reply", failed == nil { LoadingLines() }
    } else if !waiting.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SmallHead(text: "Waiting on your reply")
        ForEach(waiting) { c in
          Button {
            box = .reply(c)
          } label: {
            said(c, whole: false)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // One conversation: where it is, your agent's read of it, then its last words (on the sheet, the last few comments).
  private func said(_ c: Conversation, whole: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if let path = c.path {
        Text(path + (c.line.map { ":\($0)" } ?? "")).mono(12).foregroundStyle(Theme.pencil).lineLimit(1).truncationMode(.head)
      }
      if !whole, let gist = c.take?.gist, !gist.isEmpty { Lead(label: "\(store.agent):", text: gist) }
      ForEach(c.comments.suffix(whole ? 3 : 1)) { m in
        // Briefly: its paragraphs run on as one.
        let body = whole ? m.body ?? "" : (m.body ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
        Lead(label: m.author ?? "", text: body, color: Theme.ink).lineLimit(whole ? 8 : 4)
      }
      if !whole { Text("Reply").sans(13, 550).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2) }
    }
    .padding(.leading, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) { Theme.ruleStrong.frame(width: 2) }
    .contentShape(Rectangle())
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
      out.append(.init("by \(c.author ?? c.by ?? "")\(c.authorBot == true ? " (bot)" : "")"))
    }
    // Amber only on yours, where it's work for you; in Merging your agent has it, so it stays pencil.
    if let stage = c.stage {
      out.append(.init(stage, stage == "changes requested" && c.mine && c.inflight != true ? Theme.amber : Theme.pencil))
    }
    out.append(.init(Words.age(c.resolvedAt ?? c.doneAt ?? c.waitingSince, now: store.now)))
    if let n = item?.commentsTotal, n > 0 { out.append(.init(Words.plural(n, "comment"))) }
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

  @ViewBuilder
  private func aiBlock(_ c: Card) -> some View {
    let open = (item?.state ?? "open") == "open"
    if let ai {
      VStack(alignment: .leading, spacing: 8) {
        FlowLine(spacing: 8) {
          Text(Words.verdict[ai.verdict ?? ""] ?? Words.capitalized(ai.verdict ?? ""))
            .sans(15, 650, tracking: -0.01).foregroundStyle(ai.verdict == "skip" ? Theme.pencil : Theme.ink)
          if let risk = ai.risk { RiskMeter(risk: risk) }
          if ai.risk != "low", let reason = ai.riskReasons.first?.why { Text(reason).sans(13).foregroundStyle(Theme.pencil) }
          if aiStale { Text("on an earlier commit").sans(13).foregroundStyle(Theme.pencil) }
        }
        if let summary = ai.summary, !summary.isEmpty { Prose(text: summary, size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3) }
        if let since = ai.since, !since.isEmpty { Lead(label: "Since your review:", text: since) }
        // No diff here for the notes to sit in, so the concerns are always listed.
        if let concerns = ai.concerns, !concerns.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(concerns, id: \.self) { concern in
              Prose(text: concern, size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Theme.ruleStrong.frame(width: 2) }
            }
          }
        } else {
          Text("No concerns.").sans(13).foregroundStyle(Theme.pencil)
        }
      }
      .padding(.top, 2)
    } else if generating {
      Text("\(store.agent) is reviewing it.").sans(13).foregroundStyle(Theme.pencil)
    } else if c.mine {
      // Your own PR says what you wrote of it until a review exists, as the window's: its description's first paragraph.
      if review?.aiError == nil, let first = item?.body?.split(whereSeparator: \.isNewline).first, !first.isEmpty {
        Prose(text: String(first), size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3)
      }
    } else if landed {
      Text(open ? "No AI review yet." : "No AI review.").sans(13).foregroundStyle(Theme.pencil)
    }
  }

  // MARK: Its diff

  // Every file's lines in the PR's order. On an open PR a line is pressed to comment on it; a closed one only reads.
  private func diffBlock(_ c: Card, _ review: ReviewView, _ diff: DiffModel, _ proxy: ScrollViewProxy) -> some View {
    let can = item?.state == "open" && review.diffHead != nil
    return VStack(alignment: .leading, spacing: 6) {
      SmallHead(text: Words.plural(review.files.isEmpty ? diff.list.count : review.files.count, "file") + " changed").id("diff")
      DiffView(
        model: diff, files: review.files, conversation: review.conversation,
        sent: Diff.pending(sent, in: review.conversation, me: store.me), github: c.url.flatMap { URL(string: $0 + "/files") },
        comment: can ? { box = .line($0) } : nil, reply: can ? { box = .reply($0, onLine: true) } : nil,
        show: { proxy.scrollTo($0) }
      )
      // Edge to edge: a line's wash runs the page's width, its text keeps the gutter.
      .padding(.horizontal, -Theme.pad)
    }
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

// Parts of one line with a dot between them, wrapping as words do.
struct Dotted: View {
  struct Part {
    let text: String
    var color: Color = Theme.pencil
    init(_ text: String, _ color: Color = Theme.pencil) {
      self.text = text
      self.color = color
    }
  }

  let parts: [Part]

  var body: some View {
    parts.filter { !$0.text.isEmpty }.enumerated().reduce(Text("")) { line, part in
      line + (part.offset > 0 ? Text("  ·  ").foregroundStyle(Theme.faint) : Text("")) + Text(part.element.text).foregroundStyle(part.element.color)
    }
    .lineSpacing(3)
    .fixedSize(horizontal: false, vertical: true)
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
