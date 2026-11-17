import SwiftUI
import UIKit

// Ask your agent: your chat with the coordinator, as the window's (web/src/components/Chat.tsx). One conversation,
// every ask oldest first, each with what it was about and its answer; under the last one it hasn't answered, what it's
// doing. Opening it reads GET /api/asks and nothing else; only Send and Wake it spend a turn of your agent. Its
// answers are an agent's words: drawn as text (ProseBlocks), never markup.
struct ChatPage: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  @State private var about: ChatAbout
  @State private var text = ""
  @State private var woke: String?  // what Wake it came to
  @FocusState private var typing: Bool

  init(about: ChatAbout) { _about = State(initialValue: about) }

  private var key: String { about.item ?? "" }
  private var failed: String? { store.askFailed[key] }  // why the last send wasn't taken, in the desk's words
  private var off: Bool { store.asks?.on == false }
  private var sending: Bool { store.busy(Store.chat) }

  var body: some View {
    let asks = store.asks?.asks ?? []
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if !asks.isEmpty {
            ForEach(Array(asks.enumerated()), id: \.element.id) { i, a in turn(a, last: i == asks.count - 1).id(a.id) }
          } else if off {
            Text(Asking.off).sans(13).foregroundStyle(Theme.pencil).lineSpacing(3)
          } else if store.asks != nil {
            Text(Asking.empty(about.item)).sans(13).foregroundStyle(Theme.pencil).lineSpacing(3)
          }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollDismissesKeyboard(.interactively)
      // The newest turn's top: your words and the answer's lead, not the end of a long answer.
      .onChange(of: "\(asks.count) \(asks.filter { $0.answer != nil }.count) \(failed ?? "")", initial: true) {
        guard let last = asks.last else { return }
        proxy.scrollTo(last.id, anchor: .top)
        // Again once it's laid out: the first go lands where the turn was guessed to be.
        Task {
          for wait in [80, 300] {
            try? await Task.sleep(for: .milliseconds(wait))
            proxy.scrollTo(last.id, anchor: .top)
          }
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) { head }
    .openedPage()
    .safeAreaInset(edge: .bottom, spacing: 0) { box }
    .onAppear { if text.isEmpty { text = store.askDrafts[key] ?? "" } }
    .onChange(of: text) { _, typed in
      if typed.count > Words.maxAsk { text = String(typed.prefix(Words.maxAsk)) }
      store.askDrafts[key] = typed.isEmpty ? nil : typed
    }
    // Words the desk didn't take come back through the draft (Store.ask), whether or not this page was here meanwhile.
    .onChange(of: store.askDrafts[key]) { _, kept in
      if (kept ?? "") != text { text = kept ?? "" }
    }
    .onChange(of: store.asks?.coordinator?.status) { woke = nil }
    // Read on open, then on each of the desk's updates once they settle. No timer.
    .task(id: store.loads) {
      if store.asks != nil {
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
      }
      await store.readAsks()
    }
  }

  // MARK: Its head

  private var head: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("Your agent").sans(16, 650, tracking: -0.01).foregroundStyle(Theme.ink).fixedSize()
      if let item = about.item {
        Text(Asking.shortId(item)).sans(13, tabular: true).foregroundStyle(Theme.pencil).lineLimit(1).truncationMode(.middle)
        drop("Ask about nothing in particular")
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.pad)
    .frame(minHeight: 44)
    .background(Theme.paper)
    .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
  }

  // The window's x: one step wider. What you'd typed goes with you.
  private func drop(_ says: String) -> some View {
    Button {
      let wider = about.wider
      let to = wider.item ?? ""
      if to != key {
        store.askDrafts[key] = nil
        if text.isEmpty { text = store.askDrafts[to] ?? "" } else { store.askDrafts[to] = text }
      }
      about = wider
    } label: {
      Text("\u{00D7}").sans(17).foregroundStyle(Theme.pencil)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle().inset(by: -10))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(says)
  }

  // MARK: The log

  private func turn(_ a: Ask, last: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(a.text ?? "").sans(14).foregroundStyle(Theme.ink).lineSpacing(3)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.wash, in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 36)
        .frame(maxWidth: .infinity, alignment: .trailing)
      meta(a).frame(maxWidth: .infinity, alignment: .trailing)
      if let answer = a.answer {
        ProseBlocks(text: answer.text ?? "")
        Text(Words.sinceText(answer.at, now: store.now)).sans(12.5, tabular: true).foregroundStyle(Theme.pencil)
      } else if last {
        waiting(a)
      }
    }
  }

  // When, then what it was about: its item (a press opens it), the lines, the thread (on GitHub).
  private func meta(_ a: Ask) -> some View {
    let parts = Asking.meta(a, now: store.now, agent: store.agent)
    return FlowLine(spacing: 0) {
      ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          if i > 0 { Text("·").foregroundStyle(Theme.faint).padding(.horizontal, 6) }
          if let item = a.itemId, part == Asking.shortId(item) {
            link(part) { if store.card(item) != nil { store.path.append(.item(item)) } else if let url = Words.issueURL(item) { openURL(url) } }
          } else if part == "on a thread", let url = github(a.threadUrl) {
            link(part) { openURL(url) }
          } else {
            Text(part).lineLimit(1).truncationMode(.middle)
          }
        }
      }
    }
    .sans(12.5, tabular: true)
    .foregroundStyle(Theme.pencil)
  }

  private func link(_ words: String, _ press: @escaping () -> Void) -> some View {
    Button(action: press) {
      Text(words).underline(color: Theme.ruleStrong).contentShape(Rectangle().inset(by: -12))
    }
    .buttonStyle(.plain)
  }

  // Only GitHub's own address is opened from an ask (the desk takes no other), and only claude.ai's page over https.
  private func github(_ raw: String?) -> URL? { (raw ?? "").hasPrefix("https://github.com/") ? URL(string: raw ?? "") : nil }
  private var watch: URL? { (store.asks?.coordinator?.url).flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil } }

  // What it's doing about the ask it hasn't answered: on it, queued, stuck on a permission, or stopped, with a way to
  // see it or wake it.
  private func waiting(_ a: Ask) -> some View {
    let wait = Wait(ask: a.id, live: store.asks?.coordinator)
    let color: Color = { if case .cantRun = wait { Theme.red } else if case .step = wait { Theme.ink2 } else { Theme.pencil } }()
    return FlowLine(spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        if wait.busy { ProgressView().controlSize(.mini).tint(Theme.pencil).accessibilityHidden(true) }
        Prose(text: wait == .stopped ? woke ?? wait.words : wait.words, size: 13).foregroundStyle(color).lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .contentTransition(.opacity)
          .animation(.easeOut(duration: 0.2), value: wait.words)
      }
      if wait == .stopped {
        Button("Wake it") {
          Task { woke = await store.wake(ask: a.id, toast: false) ? "Asked it again" : Words.sentence(store.whyNot ?? "It wasn't sent") }
        }
        .buttonStyle(PlainAct())
        .disabled(store.busy(Store.agentWake))
      }
      if let says = wait.link, let watch {
        Button {
          openURL(watch)
        } label: {
          Text(says).sans(13).underline(color: Theme.ruleStrong).foregroundStyle(Theme.pencil).frame(minHeight: 28)
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityElement(children: .contain)
  }

  // MARK: The box

  // Your agent's open questions about the item, the spot the next ask carries, then Back, the field and Send.
  private var box: some View {
    let questions = (store.queue?.inquiries ?? []).filter { Words.isCoordinator($0.from) && $0.itemId == about.item && $0.answer == nil && !store.leaving.contains($0.id) }
    let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return VStack(spacing: 0) {
      NoticeStack()
      VStack(alignment: .leading, spacing: 6) {
        ForEach(questions) { q in
          HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Your agent asks: \(q.question ?? "")").lineLimit(1)
            Text("·").foregroundStyle(Theme.faint).padding(.horizontal, 6)
            Button {
              store.path.append(.inquiry(q.id))
            } label: {
              Text("Answer").underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2).fixedSize().contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
          }
        }
        if let spot = about.spot {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("On \(spot)").lineLimit(1).truncationMode(.middle)
            drop("Ask about the whole PR instead")
          }
        }
        if off, !(store.asks?.asks ?? []).isEmpty { Text(Asking.off).fixedSize(horizontal: false, vertical: true) }
        if let failed { Text(failed).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
        HStack(alignment: .bottom, spacing: 8) {
          Button {
            if !store.path.isEmpty { store.path.removeLast() }
          } label: {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink2)
              .frame(width: 26, height: 40, alignment: .leading)
              .contentShape(Rectangle().inset(by: -10))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Back")
          TextField(off ? "Your agent is off" : "Ask or tell it something", text: $text, axis: .vertical)
            .sans(15).foregroundStyle(Theme.ink).lineLimit(1...6).focused($typing).disabled(off)
            .padding(.init(top: 9, leading: 12, bottom: 9, trailing: 12))
            .background(off ? Theme.wash : Theme.sheet, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(off ? Theme.rule : Theme.ruleStrong, lineWidth: 1))
            .accessibilityLabel("Your words to your agent")
          if !off {
            Button(sending ? "Sending…" : "Send", action: send).buttonStyle(AccentAct()).disabled(empty || sending)
              .padding(.bottom, 2)
          }
        }
      }
      .sans(12.5)
      .foregroundStyle(Theme.pencil)
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.paper)
      .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
    }
  }

  // Emptied at once, as the window's box; a refusal puts your words back, with the desk's own in red.
  private func send() {
    let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !words.isEmpty, !sending, !off else { return }
    let about = about
    text = ""
    Task { await store.ask(words, about: about) }
  }
}

// An agent's words as the blocks they were written in (Blocks.parse): paragraphs, lists, bold, `code`, and a code block
// on the sheet with a quiet Copy that keeps its fence. Text only: a URL is shown, never followed.
struct ProseBlocks: View {
  let blocks: [Block]
  var size: CGFloat = 14
  var color = Theme.ink
  @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 100
  @State private var copied: Set<Int> = []

  init(text: String, size: CGFloat = 14) {
    blocks = Blocks.parse(text)
    self.size = size
  }

  init(blocks: [Block], size: CGFloat = 14, color: Color = Theme.ink) {
    self.blocks = blocks
    self.size = size
    self.color = color
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
        switch block {
        case .p(let spans): line(spans)
        case .ul(let items): list(items.map { ("\u{2022}", $0) })
        case .ol(let start, let items): list(items.enumerated().map { ("\(start + $0.offset).", $0.element) })
        case .pre(let code, let info): pre(code, info, i)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func line(_ spans: [Span]) -> some View {
    let s = size * scale / 100
    var out = AttributedString()
    for span in spans {
      var run = AttributedString(span.text)
      run.font = Font(span.code ? Typeface.mono.font(s * 0.9, weight: span.bold ? 600 : 400) : Typeface.sans.font(s, weight: span.bold ? 600 : 400))
      out += run
    }
    return Text(out).foregroundStyle(color).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
  }

  private func list(_ items: [(String, [Span])]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(item.0).sans(size, tabular: true).foregroundStyle(Theme.pencil).frame(minWidth: 14, alignment: .trailing)
          line(item.1)
        }
      }
    }
  }

  // Wrapped, not scrolled: no part of a command hides past the block's edge (and a sideways scroll would fight the swipe back).
  private func pre(_ code: String, _ info: String, _ i: Int) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(code).mono(12.5).foregroundStyle(Theme.ink).lineSpacing(3)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      Button {
        UIPasteboard.general.string = Blocks.fencedCopy(code, info: info)
        copied.insert(i)
      } label: {
        Text(copied.contains(i) ? "Copied" : "Copy").sans(12.5).foregroundStyle(Theme.ink2)
          .padding(.horizontal, 6).frame(minHeight: 30)
          .contentShape(Rectangle().inset(by: -7))
      }
      .buttonStyle(.plain)
      .accessibilityHint("Copies it with its fence, to paste on GitHub")
    }
  }
}
