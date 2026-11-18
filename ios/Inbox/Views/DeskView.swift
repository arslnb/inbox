import SwiftUI

// The desk: one stack whose root is a list page. The window's sidebar (Inbox, Blocked, a hairline, Merging, Archive)
// is the title's menu; Settings is the icon beside it. An item, a question or a session pushes its own page.
struct DeskView: View {
  @Environment(Store.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack(path: $store.path) {
      ListPage()
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .item(let id): ItemPage(id: id)
          case .inquiry(let id): InquiryPage(id: id)
          case .session(let id): SessionPage(id: id)
          case .chat(let about): ChatPage(about: about)
          }
        }
    }
    .sheet(isPresented: $store.showSettings) { SettingsSheet() }
    .sheet(item: $store.noting) { noting in NoteSheet(note: noting.note, draft: store.noteDraft) }
    #if DEBUG
      .task(id: store.loads) { store.openDebugNote() }
    #endif
    .confirmationDialog("Snooze", isPresented: Binding(get: { store.snoozing != nil }, set: { if !$0 { store.snoozing = nil } }), presenting: store.snoozing) { card in
      ForEach(SnoozeOption.all(card)) { option in
        Button(option.label) { store.act(card.id, name: card.shortRef, "snooze", snooze: option) }
      }
    }
  }
}

struct ListPage: View {
  @Environment(Store.self) private var store

  var body: some View {
    @Bindable var store = store
    Group {
      switch store.page {
      case .inbox: InboxList()
      case .blocked: BlockedList()
      case .merging: MergingList()
      case .archive: ArchiveList()
      }
    }
    .background(Theme.sheet)
    // One filter for the four pages, as the window's search.
    .safeAreaInset(edge: .top, spacing: 0) { FilterBar() }
    // An opened page has them above its own bar.
    .safeAreaInset(edge: .bottom, spacing: 0) { NoticeStack() }
    // Whether your latest ask still waits, for the menu's line: read once, then again only while one waits. Free.
    .task(id: store.loads) {
      if store.loads > 0, store.asksAgent, store.asks == nil || Asking.waiting(store.asks) { await store.readAsks() }
    }
    .navigationTitle(store.page.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Theme.side, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      // The page's name is the menu at the leading edge; the title itself only names the way back from an opened item.
      ToolbarItem(placement: .principal) { Text("") }
      ToolbarItem(placement: .topBarLeading) {
        Menu {
          Picker("Page", selection: $store.page) {
            Text(store.inboxCount > 0 ? "Inbox  \(store.inboxCount)" : "Inbox").tag(Page.inbox)
            Text("Blocked").tag(Page.blocked)
          }
          .pickerStyle(.inline)
          .labelsHidden()
          Picker("Page", selection: $store.page) {
            Text("Merging").tag(Page.merging)
            Text("Archive").tag(Page.archive)
          }
          .pickerStyle(.inline)
          .labelsHidden()
          // The window's New note (its sidebar's, ⌘N): a note to yourself lands on the Inbox.
          Divider()
          Button("New note") { store.noting = Noting() }
          // The window's Ask your agent (its sidebar's foot): your chat, about nothing in particular. Not with your agent off.
          if store.asksAgent {
            Divider()
            Button(Asking.waiting(store.asks) ? "Your agent · waiting" : "Ask your agent") { store.openChat() }
          }
        } label: {
          HStack(spacing: 7) {
            Mark().fill(Theme.accentInk).frame(width: 24, height: 24)
            Text(store.page.name).sans(16, 650, tracking: -0.01).foregroundStyle(Theme.ink)
            if store.page == .inbox, store.inboxCount > 0 {
              // White on the brand's purple, as the sidebar's count.
              Text("\(store.inboxCount)").sans(11.5, 600, tabular: true).foregroundStyle(.white)
                .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                .background(Theme.pill, in: Capsule())
            }
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.pencil)
          }
          .padding(.horizontal, 4)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .accessibilityLabel("\(store.page.name), choose a page")
        .accessibilityIdentifier("page-menu")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.showSettings = true
        } label: {
          SettingsIcon().stroke(Theme.pencil, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 20)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
      }
    }
  }
}

// MARK: List pieces

extension View {
  // A row on the sheet, edge to edge, a hairline under it from the text's edge.
  func deskRow() -> some View {
    listRowInsets(EdgeInsets())
      .listRowBackground(Theme.sheet)
      .listRowSeparatorTint(Theme.rule)
      .alignmentGuide(.listRowSeparatorLeading) { _ in Theme.pad }
      .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
  }

  // A heading or a quiet line: on the paper, no hairline of its own.
  func deskLine(_ background: Color = Theme.sheet) -> some View {
    listRowInsets(EdgeInsets()).listRowBackground(background).listRowSeparator(.hidden)
  }

  func deskList() -> some View {
    listStyle(.plain)
      .contentMargins(.top, 0, for: .scrollContent)
      .listSectionSpacing(0)  // a heading's band follows the rows above it, as the window's
      .scrollContentBackground(.hidden)
      .background(Theme.sheet)
      .environment(\.defaultMinListRowHeight, 1)
      .environment(\.defaultMinListHeaderHeight, 1)
  }
}

// A row that opens something: a press tints it as the window's pointer does.
struct RowPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.background(configuration.isPressed ? Theme.ink.opacity(0.06) : Color.clear)
  }
}

// A card's row with everything a paired device may do to it: a tap opens it; a swipe or a long press acts.
struct CardLine: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  let card: Card
  let variant: RowVariant
  var guides: [Lists.Guide] = []  // Blocked's tree: the row sits a level in per guide

  var body: some View {
    Button {
      store.path.append(.item(card.id))
    } label: {
      CardRow(card: card, variant: variant, now: store.now, me: store.me)
        .padding(.leading, CGFloat(min(guides.count, TreeGuides.most)) * TreeGuides.step)
        .overlay(alignment: .topLeading) { if !guides.isEmpty { TreeGuides(guides: guides).padding(.leading, Theme.pad) } }
    }
    .buttonStyle(RowPress())
    .deskRow()
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if card.inflight != true {
        if card.active {
          Button("Done") { store.act(card.id, name: card.shortRef, "done") }.tint(Theme.swipeAccent)
        } else {
          Button("Back on the desk") { store.act(card.id, name: card.shortRef, "restore") }.tint(Theme.swipeAccent)
        }
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if card.inflight != true {
        Button("Snooze") { store.snoozing = card }.tint(Theme.swipeQuiet)
      }
    }
    .contextMenu { CardMenu(card: card) }
  }
}

// A row's menu, in the window's order and words: Done or Back on the desk, Snooze, Move to …, Close on GitHub; then the
// phone's own Mute and its way out to GitHub. Every other write is on its page.
struct CardMenu: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  let card: Card

  var body: some View {
    if card.inflight != true {
      if card.active {
        Button("Done") { store.act(card.id, name: card.shortRef, "done") }
      } else {
        Button("Back on the desk") { store.act(card.id, name: card.shortRef, "restore") }
      }
      Menu("Snooze") {
        ForEach(SnoozeOption.times + [SnoozeOption.activity]) { option in
          Button(option.label) { store.act(card.id, name: card.shortRef, "snooze", snooze: option) }
        }
        let waits = SnoozeOption.waits(card)
        if !waits.isEmpty {
          Divider()
          ForEach(waits) { option in
            Button(option.label) { store.act(card.id, name: card.shortRef, "snooze", snooze: option) }
          }
        }
      }
      ForEach(Lists.moves(card), id: \.self) { to in
        Button("Move to \(Lists.sectionName[to] ?? to)") { store.act(card.id, name: card.shortRef, to) }
      }
      // One press, as the window's menu: the toast's Undo reopens a PR.
      if card.actions?.contains("close") == true {
        Button("Close on GitHub") { Task { await store.github(card, "close") } }
      }
      if !card.mine {
        if card.status == "muted" {
          Button("Unmute") { store.act(card.id, name: card.shortRef, "unmute") }
        } else {
          Button("Mute") { store.act(card.id, name: card.shortRef, "mute") }
        }
      }
      Divider()
    } else {
      // Merging's row: the one thing its menu writes.
      Button("Back to the desk") { Task { await store.backToDesk(card) } }
      Divider()
    }
    if let url = card.url.flatMap(URL.init(string:)) {
      Button("Open on GitHub") { openURL(url) }
      Button("Copy GitHub link") {
        UIPasteboard.general.string = url.absoluteString
        store.flash("Copied the GitHub link to \(card.shortRef)")
      }
    }
  }
}

// MARK: Inbox

// The main page: Urgent (agents' questions, the sessions that need you and your due reminders first), Standard and FYI,
// each in the desk's order.
struct InboxList: View {
  @Environment(Store.self) private var store
  @State private var allFyi = false  // Show more was pressed: until you leave the page

  var body: some View {
    if let view = store.queue {
      // The filter keeps cards and notes; an agent's question and a session that needs you always show.
      let filtering = store.filtering
      let active = view.sessions.filter { $0.status == "active" && !store.leaving.contains($0.id) }
      let total = { (list: [Card]?) in (list ?? []).filter { !store.leaving.contains($0.id) }.count }
      let urgent = store.shown(view.inbox?.urgent ?? [])
      let standard = store.shown(view.inbox?.standard ?? [])
      let fyi = store.shown(view.inbox?.fyi ?? [])
      // Your notes lead their sections: due reminders then urgent ones in Urgent, the rest in Standard and FYI.
      let urgentNotes = store.shown(view.notes?.due) + store.shown(view.notes?.urgent)
      let open = store.shown(view.notes?.open)
      let fyiNotes = store.shown(view.notes?.fyi)
      let asked = view.inquiries.filter { !store.leaving.contains($0.id) }
      let lead = asked.count + active.count + urgentNotes.count
      let any = lead + urgent.count + open.count + standard.count + fyiNotes.count + fyi.count > 0
      // A new desk's first minutes, in the desk's words; not while filtering.
      let first = filtering ? nil : view.firstPass?.line
      ScrollViewReader { proxy in
        List {
          if let first, any { QuietLine(text: first, size: 14).deskLine() }
          if lead + urgent.count > 0 {
            section("urgent", "Urgent", lead + total(view.inbox?.urgent), matched: urgent.count) {
              ForEach(asked) { q in
                Button {
                  store.path.append(.inquiry(q.id))
                } label: {
                  InquiryRow(q: q, now: store.now)
                }
                .buttonStyle(RowPress()).deskRow()
                .contextMenu {
                  Button("Answer") { store.path.append(.inquiry(q.id)) }
                  Divider()
                  // Left unanswered: the agent decides itself.
                  Button("Dismiss") { Task { await store.answer(q, text: nil) } }
                }
              }
              ForEach(active) { s in SessionLine(s: s) }
              ForEach(urgentNotes) { n in NoteLine(n: n) }
              ForEach(urgent) { c in CardLine(card: c, variant: .active) }
            }
          }
          if open.count + standard.count > 0 {
            section("standard", "Standard", open.count + total(view.inbox?.standard), matched: standard.count) {
              ForEach(open) { n in NoteLine(n: n) }
              ForEach(standard) { c in CardLine(card: c, variant: .active) }
            }
          }
          if fyiNotes.count + fyi.count > 0 {
            let cut = Lists.fyiCut(fyi.count, all: allFyi, filtering: filtering)
            section("fyi", "FYI", fyiNotes.count + total(view.inbox?.fyi), matched: fyi.count) {
              ForEach(fyiNotes) { n in NoteLine(n: n) }
              ForEach(cut.map { Array(fyi.prefix($0)) } ?? fyi) { c in CardLine(card: c, variant: .active) }
              if let cut {
                Button {
                  allFyi = true
                } label: {
                  Text("Show \(fyi.count - cut) more").sans(13).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2)
                    .padding(.horizontal, Theme.pad)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .deskLine()
              }
            }
          }
          if !any {
            if let first { QuietLine(text: first).deskLine() } else { QuietLine(text: filtering ? "No matches." : "Nothing needs you right now.").deskLine() }
          }
          if let n = view.reviewing, n > 0 {
            QuietLine(
              text: n == 1
                ? "1 more PR reaches you once \(store.agent) has reviewed it."
                : "\(n) more PRs reach you once \(store.agent) has reviewed them.", size: 14
            )
            .deskLine()
          }
        }
        .deskList()
        .refreshable { await store.refresh() }
        #if DEBUG
          .task(id: store.loads) {
            guard let to = store.scrollTo, store.loads > 0 else { return }
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo(to, anchor: .top)
          }
        #endif
      }
    } else {
      Waiting()
    }
  }

  // A section the filter has matches in opens, and stays open until the filter clears (its heading is no toggle then).
  @ViewBuilder
  private func section<Rows: View>(_ key: String, _ label: String, _ count: Int, matched: Int, @ViewBuilder rows: () -> Rows) -> some View {
    let forced = store.filtering && matched > 0 && store.folded.contains(key)
    let open = !store.folded.contains(key) || forced
    Section {
      if open { rows() }
    } header: {
      GroupHead(label: label, count: "\(count)", open: open, toggle: forced ? nil : { store.folded.formSymmetricDifference([key]) }).deskHead().id(key)
    }
  }
}

extension View {
  func deskHead() -> some View { listRowInsets(EdgeInsets()).textCase(nil) }
}

// Before the first answer: bars while it's on its way, the first-sync line on a desk that never synced, and nothing
// at all once the desk turned out to be away or refused the read (its bubble says so).
struct Waiting: View {
  @Environment(Store.self) private var store

  var body: some View {
    ScrollView {
      if store.offline || store.starting != nil || store.broken != nil || store.refused != nil {
        Color.clear.frame(height: 1)
      } else if let o = store.overview, o.syncedAt == nil {
        QuietLine(text: "Getting your PRs from GitHub…")
      } else {
        LoadingRows()
      }
    }
    .background(Theme.sheet)
    .refreshable { await store.refresh() }
  }
}

// A note's row: a tap opens it in the note box to change it; a swipe is Done, as a card's. Its menu is NoteMenu's.
struct NoteLine: View {
  @Environment(Store.self) private var store
  let n: Note

  private var text: String { n.text ?? "" }

  var body: some View {
    Button {
      store.noting = Noting(note: n)
    } label: {
      NoteRow(n: n, now: store.now)
    }
    .buttonStyle(RowPress())
    .deskRow()
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Done") { Task { await store.doneNote(n) } }.tint(Theme.swipeAccent)
    }
    .contextMenu {
      Button("Done") { Task { await store.doneNote(n) } }
      // There now: a reminder it had is dropped.
      ForEach(Lists.moves(n, now: store.now), id: \.self) { to in
        Button("Move to \(Lists.sectionName[to] ?? to)") { Task { await store.saveNote(n, text: text, remind: "", section: to) } }
      }
      // A note has no activity to wait on: the time becomes its reminder.
      Menu("Snooze") {
        ForEach(SnoozeOption.times) { option in
          Button(option.label) { Task { await store.saveNote(n, text: text, remind: option.until) } }
        }
      }
      Divider()
      Button("Change note") { store.noting = Noting(note: n) }
      Button("Copy text") {
        UIPasteboard.general.string = text
        store.flash("Copied the note")
      }
    }
  }
}

struct SessionLine: View {
  @Environment(Store.self) private var store
  let s: SessionCard

  var body: some View {
    Button {
      store.path.append(.session(s.id))
    } label: {
      SessionRow(s: s, now: store.now)
    }
    .buttonStyle(RowPress())
    .deskRow()
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Done") { store.act(s.id, name: s.name ?? "", "done") }.tint(Theme.swipeAccent)
    }
    .contextMenu {
      Button("Done") { store.act(s.id, name: s.name ?? "", "done") }
      // A session snoozes until a time; done brings it back when it moves on.
      Menu("Snooze") {
        ForEach(SnoozeOption.times) { option in
          Button(option.label) { store.act(s.id, name: s.name ?? "", "snooze", snooze: option) }
        }
      }
      // Its first action, as the window's menu, when a phone can do it: Open and the attach command are for the desk's computer.
      if let first = s.actions?.first, first == "kick" || first == "resume", let label = Words.sessionAction[first] {
        Divider()
        Button(label) { Task { await store.kick(s) } }
      }
    }
  }
}

// MARK: Blocked

// What can't move yet, a chain's rows together in the desk's order, each under the PR it needs.
struct BlockedList: View {
  @Environment(Store.self) private var store

  var body: some View {
    if let view = store.queue {
      let all = (view.sections?.blocked ?? []).filter { !store.leaving.contains($0.id) }
      let cards = store.shown(all)
      let filtering = store.filtering
      List {
        if cards.isEmpty {
          QuietLine(text: filtering ? "No matches." : "Nothing is blocked.").deskLine()
        } else {
          Section {
            // A tree in the desk's order; filtered, some of it is missing, so it lies flat.
            let guides = filtering ? [] : Lists.treeGuides(cards.map { $0.depth ?? 0 })
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
              CardLine(card: c, variant: .blocked, guides: guides.isEmpty ? [] : guides[i])
            }
          } header: {
            GroupHead(label: "Blocked", count: filtering ? "\(cards.count) of \(all.count)" : "\(all.count)").deskHead()
          }
        }
      }
      .deskList()
      .refreshable { await store.refresh() }
    } else {
      Waiting()
    }
  }
}

// MARK: Archive

// What's done: your reminders still to come, what you finished and what the world dealt with, then (folded) what's
// snoozed or muted and what your rules hide.
struct ArchiveList: View {
  @Environment(Store.self) private var store

  var body: some View {
    if let view = store.queue {
      let gone = { (list: [Card]) in list.filter { !store.leaving.contains($0.id) } }
      let later = store.shown(view.notes?.later)
      let archive = gone(Lists.archive(view))
      let cleared = gone(Lists.cleared(view))
      let hidden = gone(view.hidden)
      let filtering = store.filtering
      List {
        if later.isEmpty && store.shown(archive + cleared + hidden).isEmpty {
          QuietLine(text: filtering ? "No matches." : "Nothing here yet: what you finish, and what's dealt with, lands here.").deskLine()
        }
        if !later.isEmpty {
          Section {
            ForEach(later) { n in NoteLine(n: n) }
          } header: {
            GroupHead(label: "Reminders", count: "\(later.count)").deskHead()
          }
        }
        group("archive", "Archive", archive) { Lists.archiveNote($0) }
        group("cleared", "Snoozed or muted", cleared) { Words.clearedText($0, now: store.now) }
        group("hidden", "Hidden by rules", hidden) { Lists.hiddenNote($0) }
      }
      .deskList()
      .refreshable { await store.refresh() }
    } else {
      Waiting()
    }
  }

  // While filtering: only groups with a match, each opened by it, counted "3 of 12".
  @ViewBuilder
  private func group(_ key: String, _ label: String, _ all: [Card], note: @escaping (Card) -> String) -> some View {
    let cards = store.shown(all)
    if !cards.isEmpty {
      let forced = store.filtering && store.folded.contains(key)
      let open = !store.folded.contains(key) || forced
      Section {
        if open { ForEach(cards) { c in CardLine(card: c, variant: .note(note(c))) } }
      } header: {
        GroupHead(
          label: label, count: store.filtering ? "\(cards.count) of \(all.count)" : "\(all.count)", open: open,
          toggle: forced ? nil : { store.folded.formSymmetricDifference([key]) }
        )
        .deskHead()
      }
    }
  }
}

// MARK: Merging

// Your PRs handed off for merge: how your agent is, what each PR waits on with the agent's latest note, then what landed.
struct MergingList: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let view = store.inflight {
        let shown = Set(store.shown((view.live + view.landed).map(\.card)).map(\.id))
        let live = view.live.filter { shown.contains($0.card.id) }
        let landed = view.landed.filter { shown.contains($0.card.id) }
        ScrollViewReader { proxy in
        List {
          if let c = view.coordinator { agentLine(c).deskLine() }
          if live.isEmpty {
            QuietLine(text: store.filtering ? "No matches." : "Nothing in Merging yet: hand off one of your PRs for merge when you're done with it.").deskLine()
          }
          ForEach(parts(live), id: \.first?.id) { part in
            // The desk sends a stack's rows together, bottom first: two or more sit under one quiet line.
            if part.count > 1, let s = part[0].card.stack {
              Text("Stack on \(s.id.flatMap { view.stacks?[$0]?.base } ?? "its base") · \(s.size ?? part.count) open")
                .sans(13).foregroundStyle(Theme.pencil)
                .padding(.init(top: 12, leading: Theme.pad, bottom: 2, trailing: Theme.pad))
                .frame(maxWidth: .infinity, alignment: .leading)
                .deskLine()
            }
            ForEach(part) { row in line(row) }
          }
          if !view.work.isEmpty {
            Section {
              ForEach(view.work) { w in WorkLine(w: w) }
            } header: {
              GroupHead(label: "\(store.agent)'s work", count: "\(view.work.count)").deskHead().id("work")
            }
          }
          if !landed.isEmpty {
            Section {
              ForEach(landed) { row in line(row) }
            } header: {
              GroupHead(label: "Merged", count: "\(landed.count)").deskHead()
            }
          }
        }
        .deskList()
        .refreshable { await store.refresh() }
        #if DEBUG
          .task(id: store.loads) {
            guard let to = store.scrollTo else { return }
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo(to, anchor: .top)
          }
        #endif
        }
      } else {
        Waiting()
      }
    }
    .task { await store.openMerging() }
  }

  private func parts(_ rows: [InflightView.Row]) -> [[InflightView.Row]] {
    var out: [[InflightView.Row]] = []
    for r in rows {
      if let stack = r.card.stack?.id, let last = out.last, last[0].card.stack?.id == stack {
        out[out.count - 1].append(r)
      } else {
        out.append([r])
      }
    }
    return out
  }

  private func line(_ row: InflightView.Row) -> some View {
    Button {
      store.path.append(.item(row.card.id))
    } label: {
      MergingRow(row: row, now: store.now)
    }
    .buttonStyle(RowPress())
    .deskRow()
    .contextMenu { CardMenu(card: row.card) }
  }

  // One quiet line: how your agent is, where to watch it, and Wake it (Start it now, Try again), as the window's.
  @ViewBuilder
  private func agentLine(_ c: InflightView.Coordinator) -> some View {
    Group {
      if c.on != true {
        Text("Your agent is off in Settings → Agent.").foregroundStyle(Theme.pencil)
      } else if let error = c.error, !error.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Lead(label: "Your agent can't run:", text: error, labelColor: Theme.red)
          wake("Try again")
        }
      } else if c.id == nil {
        let says = Text("Your agent starts on your first hand-off or ask.").foregroundStyle(Theme.pencil)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            says.fixedSize()
            wake("Start it now")
          }
          VStack(alignment: .leading, spacing: 6) {
            says
            wake("Start it now")
          }
        }
      } else {
        // One line; where it doesn't fit (large text) each goes whole to the next, with no dot at the break.
        DotFlow {
          Text("Your agent").foregroundStyle(Theme.pencil).fixedSize()
          if let url = c.url.flatMap(URL.init(string:)) {
            Text("·").foregroundStyle(Theme.faint)
            Button {
              openURL(url)
            } label: {
              // One line of small text: its touch reaches into the room around it.
              Text("Watch on claude.ai").underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2).fixedSize()
                .contentShape(Rectangle().inset(by: -13))
            }
            .buttonStyle(.plain)
          }
          Text("·").foregroundStyle(Theme.faint)
          wake("Wake it")
        }
      }
    }
    .sans(13)
    .padding(.init(top: 18, leading: Theme.pad, bottom: 12, trailing: Theme.pad))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // A turn of your agent on each press; off while one is on its way.
  private func wake(_ label: String) -> some View {
    Button {
      Task { await store.wake() }
    } label: {
      Text(label).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2).fixedSize()
        .contentShape(Rectangle().inset(by: -13))
    }
    .buttonStyle(.plain)
    .disabled(store.busy(Store.coordinator))
  }
}

// A row of "<agent>'s work", as Inflight.tsx's WorkRow: the PR's title, your ask's words or the question you answered,
// its ref, where it stands and since when. A press opens what it's about: the review, your chat, the question. Try
// again, on a failed review or ask, is its own button under the row: it spends your agent, so only a press sends it.
// An answer has none: only the session that asked can read it.
struct WorkLine: View {
  @Environment(Store.self) private var store
  let w: Work

  var body: some View {
    let ref = (w.item ?? "").split(separator: "#", maxSplits: 1).map(String.init)
    VStack(alignment: .leading, spacing: 0) {
      Button(action: open) {
        RowLines(
          title: Asking.workTitle(w),
          repo: ref.count == 2 ? ref[0].split(separator: "/").last.map(String.init) : nil, number: ref.count == 2 ? "#\(ref[1])" : nil,
          age: Words.age(Asking.workSince(w), now: store.now),
          under: Asking.workPhrase(w, agent: store.agent, now: store.now).joined(separator: "  ·  "),
          // Failed: in ink, not red; it's about the agent, not the PR.
          underInk: w.state == "failed"
        )
        .accessibilityElement(children: .combine)
      }
      .buttonStyle(RowPress())
      .accessibilityHint(w.kind == "ai_review" ? "Opens its review" : w.kind == "answer" ? "Opens the question" : "Opens your chat with your agent")
      if Asking.canRetry(w) {
        Button(action: retry) {
          Text("Try again").sans(13).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2)
            .padding(.horizontal, Theme.pad)
            .frame(minHeight: 36, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(w.kind == "ask" ? store.busy(Store.agentWake) : store.asking.contains(w.key))
      }
    }
    .deskRow()
  }

  private func open() {
    switch w.kind {
    case "ai_review": store.path.append(.item(w.key))
    case "answer": store.path.append(.inquiry(w.key))
    default: store.openChat(ChatAbout(item: w.item))
    }
  }

  private func retry() {
    if w.kind == "ask" { Task { await store.wake(ask: w.key, toast: true) } } else { store.retryReview(w.key) }
  }
}
