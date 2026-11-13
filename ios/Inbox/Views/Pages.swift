import SwiftUI

// An agent's question on its own page: the question, each answer with what it leads to (a press answers with it), then
// what it's about, everything it said and its links. Answer at its foot takes your own words. Its text is the agent's: text only.
struct InquiryPage: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  let id: String
  @State private var loaded: Inquiry?
  @State private var failed: String?
  @State private var writing = false
  @State private var draft = ""

  private var q: Inquiry? { loaded ?? store.queue?.inquiries.first { $0.id == id } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let q {
          head(q)
          // Its answers straight under the question, where a press reaches them without a scroll.
          if let answer = q.answer { answered(answer) } else if !q.options.isEmpty { options(q) }
          if let item = q.itemId { about(item, q.card ?? store.card(item)) }
          context(q)
          if !q.links.isEmpty { links(q) }
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
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let q, q.answer == nil {
        BottomBar(cta: "Answer", off: store.busy(q.id), press: { writing = true }, quiet: [Quiet(label: "Dismiss") { _ in answer(q, nil) }])
      } else {
        BottomBar()
      }
    }
    .sheet(isPresented: $writing) {
      if let q {
        WriteSheet(title: "Answer \(Words.fromName(q.from, start: false))", prompt: "Your answer", button: "Answer", draft: $draft) { words in
          let took = await store.answer(q, text: words)
          if took { back() }
          return took
        }
      }
    }
    .task(id: store.loads) {
      switch await store.fetchInquiry(id) {
      case .success(let v):
        loaded = v
        failed = nil
      case .failure(let e):
        if q == nil, e != .unreachable, e != .notDesk { failed = Words.capitalized(e.words) }
      case nil: break
      }
      #if DEBUG
        if store.debugBox == "answer", q != nil {
          store.debugBox = nil
          writing = true
        }
      #endif
    }
  }

  // One of its answers, or nil to dismiss it: sent at once, and back to the list where the toast says so.
  private func answer(_ q: Inquiry, _ text: String?) {
    Task { if await store.answer(q, text: text) { back() } }
  }

  private func back() {
    if store.path.last == .inquiry(id) { store.path.removeLast() }
  }

  private func head(_ q: Inquiry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        // "Your agent" already says whose question it is.
        if !Words.isCoordinator(q.from) { Text("Agent").sans(13, 600).foregroundStyle(Theme.accentInk) }
        Dotted(parts: [.init(Words.fromName(q.from), Words.isCoordinator(q.from) ? Theme.accentInk : Theme.pencil), .init(Words.age(q.at, now: store.now))])
          .sans(13, tabular: true)
      }
      Text(q.question ?? "").sans(22, 650, tracking: -0.015).foregroundStyle(Theme.ink).lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // What it's about: the item's ref, title and standing; a tap opens the item here.
  private func about(_ item: String, _ card: Card?) -> some View {
    let repo = item.split(separator: "/").last.map(String.init)?.split(separator: "#").first.map(String.init) ?? item
    let number = item.split(separator: "#").last.map(String.init) ?? ""
    return Button {
      if card != nil { store.path.append(.item(item)) }
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        (Text(repo).foregroundStyle(Theme.pencil) + Text("#\(number)").foregroundStyle(Theme.ink2)).sans(13, tabular: true)
        if let card {
          Text(card.title).sans(14, 550).foregroundStyle(Theme.ink).lineLimit(2)
          Dotted(parts: [.init("by \(card.by ?? card.author ?? "")"), .init(card.stage ?? ""), .init(card.resolved ?? "")]).sans(13)
        }
      }
      .padding(.init(top: 10, leading: 14, bottom: 10, trailing: 14))
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private func context(_ q: Inquiry) -> some View {
    let paragraphs = (q.context ?? "").components(separatedBy: "\n")
      .reduce(into: [""]) { out, line in
        if line.trimmingCharacters(in: .whitespaces).isEmpty { out.append("") } else { out[out.count - 1] += (out[out.count - 1].isEmpty ? "" : "\n") + line }
      }
      .filter { !$0.isEmpty }
    return VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
        Prose(text: p, size: 15, links: true).foregroundStyle(Theme.ink).lineSpacing(5).tint(Theme.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // Each link by its label, then where it goes: an agent's link is shown before it's followed.
  private func links(_ q: Inquiry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SmallHead(text: "Links")
      ForEach(Array(q.links.enumerated()), id: \.offset) { _, l in
        let url = (l.url ?? "").hasPrefix("https://") ? URL(string: l.url ?? "") : nil
        Button {
          if let url { openURL(url) }
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(l.label ?? "").sans(14).underline(url != nil, color: Theme.ruleStrong).foregroundStyle(Theme.ink2).lineLimit(1)
              .layoutPriority(1)
            Text(Self.place(l.url ?? "")).sans(12.5).foregroundStyle(Theme.pencil).lineLimit(1).truncationMode(.middle)
          }
          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
      }
    }
  }

  // A link's place, short: its host and path, so the label leads.
  static func place(_ raw: String) -> String {
    guard let u = URLComponents(string: raw), let host = u.host else { return raw }
    return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) + (u.path.count > 1 ? u.path : "")
      + (u.fragment.map { "#\($0)" } ?? "")
  }

  // The answers, each a button that answers with it: the first is the agent's pick.
  private func options(_ q: Inquiry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
        Button {
          answer(q, o.answer)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              // Ink: the page's one accent is the bar's Answer.
              Text(o.answer ?? "").sans(15, 600).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
              if i == 0 { Text("its pick").sans(12.5).foregroundStyle(Theme.pencil).fixedSize() }
            }
            if let next = o.next, !next.isEmpty {
              Prose(text: next, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.init(top: 11, leading: 14, bottom: 12, trailing: 14))
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .top) { if i > 0 { Theme.rule.frame(height: 1) } }
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .disabled(store.busy(q.id))
        .accessibilityHint("Answers with it")
      }
    }
    .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
  }

  private func answered(_ a: Inquiry.Answer) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(a.dismissed == true ? "✓ Dismissed: it decides itself" : "✓ Answered: \(a.text ?? "")")
        .sans(14, 600).foregroundStyle(Theme.green).fixedSize(horizontal: false, vertical: true)
      if a.tracksPickup {
        Text(a.readAt != nil ? "Picked up \(Words.ago(a.readAt, now: store.now))" : "Not picked up yet")
          .sans(13).foregroundStyle(Theme.pencil)
      }
    }
  }
}

// A Claude Code or Codex session that needs you: why it's here, what it last said and where it runs. Kick and Resume
// carry it on in the background on the desk's computer; Open and its attach command are for that computer.
struct SessionPage: View {
  @Environment(Store.self) private var store
  let id: String

  private var s: SessionCard? { store.queue?.sessions.first { $0.id == id } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let s {
          VStack(alignment: .leading, spacing: 6) {
            Dotted(parts: facts(s)).sans(13)
            Text(s.name ?? "").sans(22, 650, tracking: -0.015).foregroundStyle(Theme.ink).lineSpacing(1)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.bottom, 4)
          Lead(label: Words.capitalized(s.reason ?? ""), text: "for \(Words.age(s.since, now: store.now)).", size: 15)
          if let excerpt = s.excerpt, !excerpt.isEmpty {
            Text(excerpt).sans(13.5).foregroundStyle(Theme.ink2).lineSpacing(3)
              .padding(.leading, 12)
              .overlay(alignment: .leading) { Theme.ruleStrong.frame(width: 2) }
          }
          if s.kind == "cli", s.alive == true {
            Text("It runs in a terminal: go back to it there.").sans(13).foregroundStyle(Theme.pencil)
          } else if let resets = Words.date(s.resetsAt), resets > store.now {
            Text("Kick it once its rate limit resets.").sans(13).foregroundStyle(Theme.pencil)
          } else if kick(s) == nil, s.actions?.isEmpty == false {
            // Said once, where its button would be: Open and its attach command act on the computer it runs on.
            Text("Open it on the desk's computer, where it runs.").sans(13).foregroundStyle(Theme.pencil)
          }
        } else {
          Text("This session doesn't need you any more.").sans(15).foregroundStyle(Theme.pencil)
        }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.top, 8)
      .padding(.bottom, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .openedPage()
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let s {
        BottomBar(
          // The desk refuses a kick before its rate limit resets, as the line above says.
          cta: kick(s).flatMap { Words.sessionAction[$0] }, off: store.busy(s.id) || (Words.date(s.resetsAt) ?? .distantPast) > store.now, press: { Task { if await store.kick(s) { back() } } },
          quiet: [
            Quiet(label: "Done") { _ in act(s, "done", nil) },
            // A session snoozes until a time; done brings it back when it moves on.
            Quiet(label: "Snooze", options: [SnoozeOption.times]) { act(s, "snooze", $0) },
          ])
      } else {
        BottomBar()
      }
    }
  }

  private func kick(_ s: SessionCard) -> String? { s.actions?.first { $0 == "kick" || $0 == "resume" } }

  private func act(_ s: SessionCard, _ action: String, _ snooze: SnoozeOption?) {
    store.act(s.id, name: s.name ?? "", action, snooze: snooze)
    back()
  }

  private func back() {
    if store.path.last == .session(id) { store.path.removeLast() }
  }

  // What it is and where: its kind, whether it runs, its folder (the last of its path) and branch.
  private func facts(_ s: SessionCard) -> [Dotted.Part] {
    let folder = (s.cwd ?? "").split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? (s.cwd ?? "")
    var out: [Dotted.Part] = [.init("\(Words.sessionKind[s.kind ?? ""] ?? (s.kind ?? "")) session")]
    if s.kind != "codex" { out.append(.init(s.alive == true ? "running" : "no process")) }
    return out + [.init(folder), .init(s.branch ?? "")]
  }
}

// This phone's part of Settings, and nothing else: which desk, as which device, and the way out.
struct SettingsSheet: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          row("Desk", store.address?.text ?? "")
          row("This device", store.address?.isLocal == true ? "On the desk's own computer: not paired" : (store.deviceName ?? "Paired"))
          row("App version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
          Button("Disconnect") {
            dismiss()
            store.disconnect()
          }
          .buttonStyle(PlainAct())
          .padding(.top, 20)
          Text(
            store.address?.isLocal == true
              ? "Disconnect forgets this desk's address on this phone."
              : "Disconnect forgets this phone's token. The device stays listed on the desk until you revoke it on the desk's computer: Settings → This device."
          )
          .sans(13).foregroundStyle(Theme.pencil).lineSpacing(3).padding(.top, 10)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.paper)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) { Text("Settings").sans(15, 600).foregroundStyle(Theme.ink) }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }.sans(15, 500).tint(Theme.ink2)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.paper)
  }

  private func row(_ name: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name).sans(12.5, 550).foregroundStyle(Theme.pencil)
      Text(value).sans(15).foregroundStyle(Theme.ink).textSelection(.enabled)
    }
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
  }
}

// What's wrong with the system (bubbles) and what you just did (the toast), pinned above the bottom edge.
struct NoticeStack: View {
  @Environment(Store.self) private var store

  var body: some View {
    let notices = store.notices
    VStack(spacing: 8) {
      if let toast = store.toast {
        HStack(spacing: 14) {
          Text(toast.text).sans(13).foregroundStyle(Theme.paper).lineLimit(2)
          if toast.undoable {
            Button {
              store.undo()
            } label: {
              Text("Undo").sans(13, 600).foregroundStyle(Theme.paper)
                .padding(.horizontal, 10).frame(minHeight: 28)
                .background(Theme.paper.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.init(top: 8, leading: 16, bottom: 8, trailing: toast.undoable ? 8 : 16))
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityIdentifier("toast")
      }
      ForEach(notices) { n in Bubble(notice: n) }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, notices.isEmpty && store.toast == nil ? 0 : 8)
    .frame(maxWidth: .infinity)
    .animation(.easeOut(duration: 0.16), value: store.toast)
    .animation(.easeOut(duration: 0.16), value: notices)
  }
}

struct Bubble: View {
  @Environment(Store.self) private var store
  let notice: Notice

  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          if let tone = notice.tone {
            Circle().fill(tone == .red ? Theme.red : Theme.amber).frame(width: 7, height: 7)
              .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
          }
          Text(notice.title).sans(13, notice.transient ? 500 : 600).foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let text = notice.text, !text.isEmpty {
          Prose(text: text, size: 13).foregroundStyle(Theme.pencil).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        if let fix = notice.fix, let label = notice.fixLabel {
          Button {
            if fix == .retry { store.retry() } else { store.syncNow() }
          } label: {
            Text(label).sans(13, 600).foregroundStyle(Theme.accentInk)
              .padding(.horizontal, 10).frame(minHeight: 28)
              .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8))
              .contentShape(Rectangle().inset(by: -8))
          }
          .buttonStyle(.plain)
          .disabled(notice.busy)
          .padding(.top, 6)
        }
      }
      .padding(.top, 3)
      .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.dismiss(notice)
      } label: {
        Path { p in
          p.move(to: .init(x: 4.5, y: 4.5))
          p.addLine(to: .init(x: 11.5, y: 11.5))
          p.move(to: .init(x: 11.5, y: 4.5))
          p.addLine(to: .init(x: 4.5, y: 11.5))
        }
        .stroke(Theme.pencil, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .frame(width: 16, height: 16)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle().inset(by: -6))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding(.init(top: 8, leading: 12, bottom: 10, trailing: 4))
    .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
    .shadow(color: .black.opacity(0.12), radius: 15, y: 8)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}
