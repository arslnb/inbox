import Foundation

// A PR's diff as the page draws it, from the hunks in the desk's reading order (ReviewOrder) alone: a patch's lines with
// their numbers, the files in Code changes order, the threads on their lines, and where a comment on a line goes. The
// twins of patchLines() in src/review.ts, traditional() and onLines() in src/sections.ts, threadsOn() and inlineAt() in
// web/src/view.ts. Pure: nothing here asks the desk.

struct PatchLine: Equatable, Sendable {
  enum Kind: Sendable { case add, del, context, hunk }

  let kind: Kind
  var old: Int?  // its number in the old file: a removed or an unchanged line's; a hunk's first
  var new: Int?  // its number in the new file: an added or an unchanged line's; a hunk's first
  let text: String  // without its sign; a hunk's whole @@ line
}

// Each line of a unified patch with its old- and new-file line numbers. What isn't a line of either file is left out
// ("\ No newline at end of file").
func patchLines(_ patch: String) -> [PatchLine] {
  var out: [PatchLine] = []
  var o = 0
  var n = 0
  for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
    if let h = Diff.header(line) {
      o = h.old
      n = h.new
      out.append(PatchLine(kind: .hunk, old: o, new: n, text: String(line)))
    } else if line.hasPrefix("+") {
      out.append(PatchLine(kind: .add, old: nil, new: n, text: String(line.dropFirst())))
      n += 1
    } else if line.hasPrefix("-") {
      out.append(PatchLine(kind: .del, old: o, new: nil, text: String(line.dropFirst())))
      o += 1
    } else if line.hasPrefix(" ") {
      out.append(PatchLine(kind: .context, old: o, new: n, text: String(line.dropFirst())))
      o += 1
      n += 1
    }
  }
  return out
}

// One file of the diff: its hunks in diff order. Under the fold, a file the desk folded away, with why.
struct DiffSection: Identifiable, Sendable {
  let key: String
  let path: String
  let file: Int  // index in ReviewView.files
  var level: String?  // "skip" under a ranked review's fold; nil in Code changes order
  var why: String?  // why the desk folded the file
  let hunks: [ReviewHunk]  // none for a file with no text diff
  var notes: [Int] = []  // indices into ai.notes, in reading order
  let rows: Int  // how many lines it draws, its @@ lines among them
  var marks: [String] = []  // what marking it viewed marks: its hunks', or a file's own without any
  var id: String { key }

  var additions: Int { hunks.reduce(0) { $0 + ($1.additions ?? 0) } }
  var deletions: Int { hunks.reduce(0) { $0 + ($1.deletions ?? 0) } }
}

// Where a comment goes: one line of one side of a file, and what the line says.
struct LineSpot: Hashable, Sendable {
  let path: String
  let line: Int
  let side: String  // "new" | "old": old is a removed line, numbered in the old file
  var text = ""

  // "plan.ts:23", as the window's lineName().
  var name: String { "\(Diff.splitPath(path).name):\(line)" }
  var key: String { "\(path):\(side):\(line)" }
}

// Yours from this page, shown until the conversation read again has it.
struct SentWords: Identifiable, Equatable, Sendable {
  let id = UUID()
  var spot: LineSpot?  // a comment on a line
  var thread: String?  // a reply in a thread
  let body: String
}

enum Diff {
  static let cap = 400  // a section's lines drawn on the phone; the rest are on GitHub
  static let heavy = 3000  // past this many lines in all, every file starts folded

  // "@@ -12,7 +12,9 @@ fn" as its numbers; a count left out is 1.
  static func header(_ line: some StringProtocol) -> (old: Int, oldCount: Int, new: Int, newCount: Int)? {
    guard line.hasPrefix("@@ -") else { return nil }
    let parts = line.dropFirst(4).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, parts[1].hasPrefix("+"), parts[2].hasPrefix("@@") else { return nil }
    func pair(_ s: some StringProtocol) -> (Int, Int)? {
      let p = s.split(separator: ",", omittingEmptySubsequences: false)
      guard p.count <= 2, let from = digits(p[0]) else { return nil }
      guard p.count == 2 else { return (from, 1) }
      return digits(p[1]).map { (from, $0) }
    }
    guard let a = pair(parts[0]), let b = pair(parts[1].dropFirst()) else { return nil }
    return (a.0, a.1, b.0, b.1)
  }

  private static func digits(_ s: some StringProtocol) -> Int? {
    !s.isEmpty && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } ? Int(s) : nil
  }

  // How many lines patchLines() makes of it, without making them.
  static func rows(_ patch: String) -> Int {
    patch.utf8.split(separator: 10, omittingEmptySubsequences: false).reduce(0) { n, line in
      switch line.first {
      case 43, 45, 32: n + 1  // + - space
      case 64: n + (header(Substring(line)) == nil ? 0 : 1)  // @
      default: n
      }
    }
  }

  // Code changes: every file in the PR's order, each one section with all its hunks in diff order; then, from `rest` on,
  // the files the desk folds away. No ranking, no levels.
  static func traditional(_ o: ReviewOrder) -> (list: [DiffSection], rest: Int) {
    var byFile: [Int: [ReviewHunk]] = [:]
    for h in o.chunks + o.unread + o.skipped { byFile[h.file ?? 0, default: []].append(h) }
    let number = { (h: ReviewHunk) in Int(h.id.dropFirst()) ?? 0 }
    let list = byFile.keys.sorted().map { file in
      let hunks = (byFile[file] ?? []).sorted { number($0) < number($1) }
      return section("file:\(file)", hunks.first?.path ?? "", file, level: nil, why: nil, hunks)
    }
    return (list + restOf(o), list.count)
  }

  // The files the desk folds away, each one section; a note on a file with no text diff is the file's own.
  static func restOf(_ o: ReviewOrder) -> [DiffSection] {
    o.rest.map { r in
      var s = section("rest:\(r.path ?? "")", r.path ?? "", r.file ?? 0, level: o.ranked == true ? "skip" : nil, why: r.why, r.hunks)
      s.notes = (r.notes ?? []) + s.notes
      if r.hunks.isEmpty { s.marks = [r.mark].compactMap { $0 } }
      return s
    }
  }

  static func section(_ key: String, _ path: String, _ file: Int, level: String?, why: String?, _ hunks: [ReviewHunk]) -> DiffSection {
    DiffSection(
      key: key, path: path, file: file, level: level, why: why, hunks: hunks, notes: hunks.flatMap { $0.notes ?? [] },
      rows: hunks.reduce(0) { $0 + rows($1.patch ?? "") }, marks: hunks.compactMap(\.mark))
  }

  // A section's lines, its hunks one after another.
  static func lines(_ s: DiffSection) -> [PatchLine] { s.hunks.flatMap { patchLines($0.patch ?? "") } }

  // Of a section's lines, how many are drawn and how many are left for GitHub.
  static func capped(_ rows: Int) -> (shown: Int, more: Int) {
    (min(rows, cap), max(0, rows - cap))
  }

  // Whether a line sits on one of these hunks; one that doesn't is only in the conversation.
  static func onLines(_ hunks: [ReviewHunk], line: Int, side: String) -> Bool {
    hunks.contains { h in
      guard let m = header(h.header ?? "") else { return false }
      let (from, count) = side == "old" ? (m.old, m.oldCount) : (m.new, m.newCount)
      return line >= from && line < from + count
    }
  }

  // The review threads on these hunks' lines, to show where they are; outdated ones are only in the conversation.
  static func threadsOn(_ conversation: [Conversation], path: String, hunks: [ReviewHunk]) -> [Conversation] {
    conversation.filter { c in
      guard c.kind == "thread", c.path == path, c.outdated != true, let line = c.line, let side = c.side, !side.isEmpty else { return false }
      return onLines(hunks, line: line, side: side)
    }
  }

  // Where a comment on this line goes: a removed line is the old file's, any other the new one's; a @@ line takes none.
  static func spot(_ path: String, _ l: PatchLine) -> LineSpot? {
    switch l.kind {
    case .hunk: nil
    case .del: l.old.map { LineSpot(path: path, line: $0, side: "old", text: l.text) }
    case .add, .context: l.new.map { LineSpot(path: path, line: $0, side: "new", text: l.text) }
    }
  }

  // The line a thread or a comment is on, among a section's.
  static func index(_ lines: [PatchLine], line: Int, side: String) -> Int? {
    lines.firstIndex { $0.kind != .hunk && (side == "old" ? $0.old : $0.new) == line }
  }

  // Yours from here that the conversation read again doesn't have yet.
  static func pending(_ sent: [SentWords], in conversation: [Conversation], me: String) -> [SentWords] {
    sent.filter { s in
      !conversation.contains { c in
        c.comments.contains { ($0.author ?? "").lowercased() == me.lowercased() && ($0.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == s.body }
      }
    }
  }

  // "src/planner/" and "plan.ts", so the name can stay whole while the folder truncates.
  static func splitPath(_ p: String) -> (dir: String, name: String) {
    guard let i = p.lastIndex(of: "/") else { return ("", p) }
    return (String(p[...i]), String(p[p.index(after: i)...]))
  }
}

// Which files are folded, beside how each starts (DiffModel.startsShut): those pressed away from it, and viewed ones
// opened for now. Review.tsx's isShut(), toggleFold() and markViewed().
struct Folds: Equatable {
  var flipped: Set<String> = []  // by section key
  var peek: Set<String> = []  // viewed, opened again

  // Viewed: every one of its marks is.
  static func viewed(_ s: DiffSection, _ marks: Set<String>) -> Bool { !s.marks.isEmpty && s.marks.allSatisfy(marks.contains) }

  // A viewed file stays folded until it's opened for now.
  func shut(_ s: DiffSection, starts: Bool, viewed: Bool) -> Bool {
    viewed ? !peek.contains(s.key) : starts != flipped.contains(s.key)
  }

  // A press on its header.
  mutating func press(_ s: DiffSection, viewed: Bool) {
    if viewed { peek.formSymmetricDifference([s.key]) } else { flipped.formSymmetricDifference([s.key]) }
  }

  // Viewed ticked folds it, unticked opens it.
  mutating func marked(_ s: DiffSection, on: Bool, starts: Bool) {
    peek.remove(s.key)
    if !on, starts { flipped.insert(s.key) } else if !on { flipped.remove(s.key) }
  }

  // The marks viewed as the desk has them, with what was ticked here and hasn't come back from it yet.
  static func marks(_ desk: [String], _ marking: [String: Bool]) -> Set<String> {
    var out = Set(desk)
    for (m, on) in marking {
      if on { out.insert(m) } else { out.remove(m) }
    }
    return out
  }
}

// One review's sections, and each one's lines once it has been drawn: a patch is parsed the first time it's unfolded or
// scrolled to. A new one is made for every review that lands.
@MainActor
final class DiffModel {
  struct Row: Identifiable {
    let id: String  // "<section>:<index>"
    let line: PatchLine
  }

  let list: [DiffSection]
  let rest: Int  // from here on, what the desk folded away
  let total: Int
  // Guided: the steps and where each starts, where the bugs outside them start, and how many files it leaves out.
  let guiding: Bool
  var steps: [WalkStep] = []
  var beyond = 0
  var left = 0
  private var parsed: [String: [Row]] = [:]

  // Code changes, or (with `guided`, for an order that has steps) the guided review; `bugs`: how many of ai.notes are concerns.
  init(_ order: ReviewOrder, guided: Bool = false, bugs: Int = 0) {
    guiding = guided && !(order.steps ?? []).isEmpty
    if guiding {
      let g = Diff.guided(order, bugs: bugs)
      (list, rest, steps, beyond, left) = (g.list, g.list.count, g.steps, g.beyond, g.left)
    } else {
      (list, rest) = Diff.traditional(order)
    }
    total = list.reduce(0) { $0 + $1.rows }
  }

  // A place to jump to from above the diff, as the window's sidebar lists them: a step of the guide, or a file.
  struct Stop: Identifiable, Equatable {
    let id: String  // what the page scrolls to
    var title = ""  // a step's
    var path = ""  // a file's
    var level: String?
    var notes = false  // the AI review has notes in it
  }

  // The guide's steps; in Code changes each file once, where reading reaches it, less what the desk folded away (that
  // is one line of the diff itself, "Not worth reviewing").
  var stops: [Stop] {
    if guiding { return steps.indices.map { Stop(id: "step-\($0)", title: steps[$0].title) } }
    var seen: Set<String> = []
    return list.prefix(rest).compactMap { s in
      guard seen.insert(s.path).inserted else { return nil }
      return Stop(id: s.key, path: s.path, level: s.level, notes: list.contains { $0.path == s.path && !$0.notes.isEmpty })
    }
  }

  // Code changes' files you've viewed, by path.
  func seen(_ marks: Set<String>) -> Set<String> { Set(list.filter { Folds.viewed($0, marks) }.map(\.path)) }

  // The lines it draws: its first Diff.cap.
  func rows(_ s: DiffSection) -> [Row] {
    if let have = parsed[s.key] { return have }
    let rows = Diff.lines(s).prefix(Diff.cap).enumerated().map { Row(id: "\(s.key):\($0.offset)", line: $0.element) }
    parsed[s.key] = rows
    return rows
  }

  // Folded until pressed: what the desk folded away, and every file of a diff too long to draw at once.
  // Guided, a test file too, and nothing at Claude's "skip" level is folded: a step showing it wants it read.
  func startsShut(_ s: DiffSection) -> Bool {
    guiding ? Diff.isTestPath(s.path) || total > Diff.heavy : s.level == "skip" || total > Diff.heavy
  }

  // Where a line of a file is drawn: its row, else its file's header; nil when the list doesn't have it.
  func place(path: String, line: Int, side: String) -> String? {
    let of = list.prefix(rest).filter { $0.path == path }
    guard let s = of.first(where: { Diff.onLines($0.hunks, line: line, side: side) }) ?? of.first else { return nil }
    return rows(s).first { Diff.on($0.line, line: line, side: side) }?.id ?? s.key
  }

  #if DEBUG
    // For a shot: the row of the first thread on a line, and a line of the new file by its number.
    func firstThread(_ conversation: [Conversation]) -> String? {
      for s in list.prefix(rest) {
        for c in Diff.threadsOn(conversation, path: s.path, hunks: s.hunks) {
          if let i = Diff.index(rows(s).map(\.line), line: c.line ?? 0, side: c.side ?? "new") { return "\(s.key):\(i)" }
        }
      }
      return nil
    }

    // The row of the first of the AI review's notes on a line.
    func firstNote(_ notes: [AiReview.Note]) -> String? {
      for s in list.prefix(rest) {
        for n in Diff.placed(s, notes).lines {
          if let row = rows(s).first(where: { Diff.on($0.line, line: notes[n].line ?? 0, side: notes[n].side ?? "new") }) { return row.id }
        }
      }
      return nil
    }

    func spot(_ at: String) -> LineSpot? {
      guard let colon = at.lastIndex(of: ":"), let line = Int(at[at.index(after: colon)...]) else { return nil }
      let path = String(at[..<colon])
      guard let s = list.first(where: { $0.path == path }), let i = Diff.index(rows(s).map(\.line), line: line, side: "new") else { return nil }
      return Diff.spot(path, rows(s)[i].line)
    }
  #endif
}
