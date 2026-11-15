import SwiftUI

// A PR's diff. Traditional: each file once, in the PR's order, its hunks' lines under a header that folds it; then the
// files the desk folded away, under one line. Guided (DiffModel.guiding): the review's steps, each a heading with what
// to check, then only its sections. Drawn from the order's hunks alone (PatchLines.swift, Guide.swift). Unified,
// wrapped, never scrolled sideways (that would fight the swipe back). A line is pressed to comment on it; a thread, the
// AI review's note and its "Look here" sit under their line.

struct DiffView: View {
  let model: DiffModel
  var files: [ReviewFile] = []
  var conversation: [Conversation] = []
  var sent: [SentWords] = []  // yours from this page that the conversation doesn't have yet
  var github: URL?  // the PR's Files changed, for what isn't drawn here
  var comment: ((LineSpot) -> Void)?  // nil: not open, so a line takes no comment
  var reply: ((Conversation) -> Void)?
  var ask: ((Conversation) -> Void)?  // Ask your agent, about a thread on a line
  var notes: [AiReview.Note] = []  // the AI review's, which the sections index into
  var looks: [AiReview.Look] = []  // where correctness hinges; none for a review of an earlier commit
  var bugs = 0  // the first of `notes` are its concerns: potential bugs
  var diagrams: [AiReview.Diagram] = []
  var show: (String) -> Void = { _ in }  // scrolls just far enough to bring what has this id into view
  var jump: (String) -> Void = { _ in }  // scrolls what has this id to the top
  var traditional: () -> Void = {}  // leaves the guide for every file
  @State private var flipped: Set<String> = []  // sections pressed away from how they start
  @State private var restOpen = false
  @State private var opened: Set<String> = []  // resolved threads opened
  // Code stops growing where a line would hold too little to read as one; what people said under it grows on.
  static let largest = DynamicTypeSize.accessibility1

  static let levels = ["look": "Look", "skim": "Skim", "unread": "Not read", "skip": "Skip"]
  static let statuses = ["added": "new", "removed": "deleted", "renamed": "renamed", "copied": "copied"]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
      ForEach(Array(model.list.prefix(model.rest).enumerated()), id: \.element.id) { i, s in
        if let k = model.steps.firstIndex(where: { $0.at == i }) { stepHead(k) }
        if model.guiding, i == model.beyond { guideHead("Potential bugs outside the guide").id("bugs") }
        section(s)
        // The step that ends here: on to the next one, or the guide's end.
        if let end = model.steps.indices.first(where: { (model.steps.indices.contains($0 + 1) ? model.steps[$0 + 1].at : model.beyond) == i + 1 }) {
          stepFoot(end)
        }
      }
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
        let mineNotes = Diff.placed(s, notes)
        let lookHere = Set(s.hunks.flatMap { $0.looks ?? [] }).sorted().filter(looks.indices.contains)
        // A note about the whole file sits above its diff.
        if !mineNotes.file.isEmpty { margin { ForEach(mineNotes.file, id: \.self) { n in AiNote(text: notes[n].body ?? "", bug: n < bugs) } } }
        let threads = Diff.threadsOn(conversation, path: s.path, hunks: s.hunks)
        let mine = sent.filter { w in w.spot?.path == s.path || threads.contains { $0.id == w.thread } }
        // The numbers' column: as wide as its longest.
        let digits = max(2, String(rows.last.map { max($0.line.old ?? 0, $0.line.new ?? 0) } ?? 0).count)
        ForEach(rows) { r in
          DiffLine(line: r.line, spot: Diff.spot(s.path, r.line), digits: digits, comment: comment).dynamicTypeSize(...DiffView.largest)
          if !lookHere.isEmpty || !mineNotes.lines.isEmpty { noted(r.line, lookHere, mineNotes.lines) }
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

  // MARK: The guide

  // A stop of the walk-through: "2 of 4" and its title, its words, what to check, then its sections. No colour, no box.
  private func stepHead(_ k: Int) -> some View {
    let st = model.steps[k]
    return VStack(alignment: .leading, spacing: 5) {
      (Text("\(k + 1) of \(model.steps.count)  ").foregroundStyle(Theme.pencil) + Text(st.title).foregroundStyle(Theme.ink))
        .sans(15, 600, tabular: true)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      if !st.body.isEmpty { Prose(text: st.body, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
      if !st.check.isEmpty { Lead(label: "Check:", text: st.check, size: 13.5, labelColor: Theme.ink2) }
      if !st.note.isEmpty {
        Prose(text: st.note, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true).ruled()
      }
      if !st.diagram.isEmpty, let d = diagrams.first(where: { $0.id == st.diagram }) { DiagramLines(diagram: d).padding(.top, 3) }
    }
    .padding(.horizontal, Theme.pad)
    .padding(.top, k == 0 ? 6 : 22)
    .padding(.bottom, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .id("step-\(k)")
  }

  private func guideHead(_ words: String) -> some View {
    Text(words).sans(15, 600).foregroundStyle(Theme.ink)
      .padding(.horizontal, Theme.pad).padding(.top, 22).padding(.bottom, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  // Under a step's last section: on to the next, or the guide's end and what it left out.
  @ViewBuilder
  private func stepFoot(_ end: Int) -> some View {
    if model.steps.indices.contains(end + 1) {
      quietLink("Next: \(model.steps[end + 1].title)") { jump("step-\(end + 1)") }
        .padding(.horizontal, Theme.pad).padding(.top, 4)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        Text(model.left > 0 ? "End of the guide. \(model.left == 1 ? "1 more file changes" : "\(model.left) more files change") outside it:" : "End of the guide.")
          .sans(13).foregroundStyle(Theme.pencil).fixedSize(horizontal: false, vertical: true)
        if model.left > 0 { quietLink("read every file in Traditional", traditional) }
      }
      .padding(.horizontal, Theme.pad).padding(.top, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func quietLink(_ words: String, _ press: @escaping () -> Void) -> some View {
    Button(action: press) {
      Text(words).sans(13, 550).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: The AI review on a line

  // On the paper, between the code's lines, in the sans face: what isn't code.
  private func margin(@ViewBuilder _ what: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) { what() }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.paper)
  }

  // "Look here" where correctness hinges, then the review's notes on this line.
  @ViewBuilder
  private func noted(_ l: PatchLine, _ lookHere: [Int], _ onLines: [Int]) -> some View {
    let see = lookHere.filter { Diff.on(l, line: looks[$0].line ?? 0, side: looks[$0].side ?? "new") }
    let here = onLines.filter { Diff.on(l, line: notes[$0].line ?? 0, side: notes[$0].side ?? "new") }
    if !see.isEmpty || !here.isEmpty {
      margin {
        ForEach(see, id: \.self) { i in
          let look = looks[i]
          let (line, end) = (look.line ?? 0, look.end ?? 0)
          Lead(label: "Look here\(end > line ? ", lines \(line)–\(end)" : ""):", text: look.why ?? "", size: 13.5, color: Theme.ink).ruled()
        }
        ForEach(here, id: \.self) { n in AiNote(text: notes[n].body ?? "", bug: n < bugs) }
      }
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
        SaidActions(reply: reply.map { r in { r(c) } }, url: c.url, ask: ask.map { a in { a(c) } })
      }
    }
    .ruled()
  }
}

// The AI review's note in the margin of the code. A concern says so first: it's a potential bug, its edge in amber.
struct AiNote: View {
  let text: String
  let bug: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if bug { Text("Potential bug").sans(12.5, 650).foregroundStyle(Theme.amber) }
      Prose(text: text, size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.leading, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) { (bug ? Theme.amber : Theme.ruleStrong).frame(width: 2) }
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
        Text(String((l.kind == .del ? l.old : l.new) ?? 0)).foregroundStyle(Theme.pencil).frame(width: CGFloat(digits) * char, alignment: .trailing)
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
