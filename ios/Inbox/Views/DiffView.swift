import SwiftUI

// A PR's diff in Traditional order: each file once, in the PR's order, its hunks' lines under a header that folds it;
// then the files the desk folded away, under one line. Drawn from the order's hunks alone (PatchLines.swift). Unified,
// wrapped, never scrolled sideways (that would fight the swipe back). A line is pressed to comment on it; a thread sits
// under its line.

struct DiffView: View {
  let model: DiffModel
  var files: [ReviewFile] = []
  var conversation: [Conversation] = []
  var sent: [SentWords] = []  // yours from this page that the conversation doesn't have yet
  var github: URL?  // the PR's Files changed, for what isn't drawn here
  var comment: ((LineSpot) -> Void)?  // nil: not open, so a line takes no comment
  var reply: ((Conversation) -> Void)?
  var show: (String) -> Void = { _ in }  // scrolls just far enough to bring what has this id into view
  @State private var flipped: Set<String> = []  // sections pressed away from how they start
  @State private var restOpen = false
  @State private var opened: Set<String> = []  // resolved threads opened
  // Code stops growing where a line would hold too little to read as one; what people said under it grows on.
  static let largest = DynamicTypeSize.accessibility1

  static let levels = ["look": "Look", "skim": "Skim", "unread": "Not read", "skip": "Skip"]
  static let statuses = ["added": "new", "removed": "deleted", "renamed": "renamed", "copied": "copied"]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
      ForEach(model.list.prefix(model.rest)) { s in section(s) }
      let folded = model.list.count - model.rest
      if folded > 0 {
        Button {
          restOpen.toggle()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            chevron(restOpen)
            Text("Not worth reviewing · \(folded) \(folded == 1 ? "file" : "files")").sans(13, restOpen ? 550 : 400)
              .foregroundStyle(restOpen ? Theme.ink2 : Theme.pencil)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, Theme.pad)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(restOpen ? .isSelected : [])
        if restOpen { ForEach(model.list.dropFirst(model.rest)) { s in section(s) } }
      }
    }
  }

  private func shut(_ s: DiffSection) -> Bool { model.startsShut(s) != flipped.contains(s.key) }

  @ViewBuilder
  private func section(_ s: DiffSection) -> some View {
    Section {
      if !s.hunks.isEmpty, !shut(s) {
        let rows = model.rows(s)
        let threads = Diff.threadsOn(conversation, path: s.path, hunks: s.hunks)
        let mine = sent.filter { w in w.spot?.path == s.path || threads.contains { $0.id == w.thread } }
        // The numbers' column: as wide as its longest.
        let digits = max(2, String(rows.last.map { max($0.line.old ?? 0, $0.line.new ?? 0) } ?? 0).count)
        ForEach(rows) { r in
          DiffLine(line: r.line, spot: Diff.spot(s.path, r.line), digits: digits, comment: comment).dynamicTypeSize(...DiffView.largest)
          if !threads.isEmpty || !mine.isEmpty, let at = Diff.spot(s.path, r.line) { said(at, r.line, threads, mine) }
        }
        let more = Diff.capped(s.rows).more
        if more > 0 { beyond(more) }
        Theme.rule.frame(height: 1)
      }
    } header: {
      head(s).dynamicTypeSize(...DiffView.largest).id(s.key)
    }
  }

  // MARK: A file's header

  private func head(_ s: DiffSection) -> some View {
    let file = files.indices.contains(s.file) ? files[s.file] : nil
    let (dir, name) = Diff.splitPath(s.path)
    let status = DiffView.statuses[file?.status ?? ""].map { $0 + ((file?.previousPath).map { " from \($0)" } ?? "") }
    let under = [status, s.why].compactMap { $0 }.filter { !$0.isEmpty }
    let isShut = shut(s)
    return Button {
      guard !s.hunks.isEmpty else { return }
      flipped.formSymmetricDifference([s.key])
      // Folded from its pinned header, lines down: the file's own place comes back to the top, not the one after it.
      if !isShut { Task { show(s.key) } }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          // Nothing to unfold in a file with no text diff.
          chevron(!isShut).opacity(s.hunks.isEmpty ? 0 : 1)
          if let level = s.level, let word = DiffView.levels[level] {
            Text(word).sans(13, level == "look" ? 650 : level == "skim" ? 550 : 500)
              .foregroundStyle(level == "look" ? Theme.amber : level == "skim" ? Theme.accentInk : Theme.pencil).fixedSize()
          }
          // The folder gives way from its head, so the name stays whole.
          (Text(dir).foregroundStyle(Theme.pencil) + Text(name).foregroundStyle(Theme.ink)).mono(12.5, 500).lineLimit(1).truncationMode(.head)
          Spacer(minLength: 4)
          if !s.hunks.isEmpty {
            Text("+\(s.additions) \u{2212}\(s.deletions)").sans(12.5, tabular: true).foregroundStyle(Theme.pencil).fixedSize()
          }
        }
        if !under.isEmpty {
          Text(under.joined(separator: " · ")).sans(12.5).foregroundStyle(Theme.pencil).lineLimit(2).padding(.leading, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 6)
      .frame(minHeight: 44)
      .background(Theme.paper)
      .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(s.path), \(isShut ? "folded" : "shown")")
  }

  private func chevron(_ open: Bool) -> some View {
    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
      .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 9)
      .accessibilityHidden(true)
  }

  // The lines past what's drawn here are on GitHub.
  @ViewBuilder
  private func beyond(_ more: Int) -> some View {
    let words = "\(Words.plural(more, "more line")): Open on GitHub"
    Group {
      if let github {
        Link(destination: github) { Text(words).underline(color: Theme.ruleStrong) }
      } else {
        Text(words)
      }
    }
    .sans(13).foregroundStyle(Theme.ink2)
    .padding(.horizontal, Theme.pad)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Theme.sheet)
  }

  // MARK: What was said on a line

  @ViewBuilder
  private func said(_ at: LineSpot, _ l: PatchLine, _ threads: [Conversation], _ mine: [SentWords]) -> some View {
    // A thread on an unchanged line is on either side of it.
    let here = threads.filter { $0.side == "old" ? $0.line == l.old && l.kind != .add : $0.line == l.new && l.kind != .del }
    let new = mine.filter { $0.spot?.key == at.key }
    if !here.isEmpty || !new.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(here) { c in thread(c, mine.filter { $0.thread == c.id }) }
        ForEach(new) { s in YoursSent(words: s).ruled() }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.paper)
    }
  }

  @ViewBuilder
  private func thread(_ c: Conversation, _ mine: [SentWords]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if c.resolved == true, !opened.contains(c.id) {
        // One line until it's pressed.
        Button {
          opened.insert(c.id)
        } label: {
          let first = c.comments.first
          Text("Resolved · \(first?.author ?? ""): \((first?.body ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? "")")
            .sans(13).foregroundStyle(Theme.pencil).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        if c.resolved == true { Text("Resolved").sans(13).foregroundStyle(Theme.pencil) }
        // The same drawing as under "What was said" on the page (Said.swift).
        SaidComments(comments: c.comments, mine: mine)
        SaidActions(reply: reply.map { r in { r(c) } }, url: c.url)
      }
    }
    .ruled()
  }
}

// One line of a file: its number (the old file's on a removed line), its sign, its text.
private struct DiffLine: View {
  let line: PatchLine
  let spot: LineSpot?
  let digits: Int
  let comment: ((LineSpot) -> Void)?
  @ScaledMetric(relativeTo: .body) private var char: CGFloat = 7.25  // the mono face's advance at 12

  var body: some View {
    let l = line
    if l.kind == .hunk {
      Text(l.text).mono(11).foregroundStyle(Theme.pencil).lineLimit(1)
        .padding(.horizontal, Theme.pad).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(String((l.kind == .del ? l.old : l.new) ?? 0)).foregroundStyle(Theme.faint).frame(width: CGFloat(digits) * char, alignment: .trailing)
        Text(l.kind == .add ? "+" : l.kind == .del ? "\u{2212}" : " ")
          .foregroundStyle(l.kind == .add ? Theme.green : Theme.red).frame(width: char * 2.4)
        // Wrapped under its own first letter, the numbers' column kept clear.
        Text(l.text.isEmpty ? " " : l.text).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
      }
      .mono(12)
      .padding(.leading, Theme.pad)
      .padding(.trailing, 8)
      .padding(.vertical, 1.5)
      .background(l.kind == .add ? Theme.addWash : l.kind == .del ? Theme.delWash : Theme.sheet)
      .contentShape(Rectangle())
      .onTapGesture { if let spot { comment?(spot) } }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(l.kind == .add ? "Added, line" : l.kind == .del ? "Removed, line" : "Line") \(spot?.line ?? 0): \(l.text)")
      .accessibilityAddTraits(comment == nil ? [] : .isButton)
      .accessibilityHint(comment == nil ? "" : "Comment on this line")
    }
  }
}
