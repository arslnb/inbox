import Foundation

// The guided review as the page draws it, from the desk's reading order alone: its steps' sections, what the steps leave
// out, where the AI review's notes sit, and a diagram as lines of text. The twins of walk(), isTestPath() and onLines()
// in src/sections.ts, the review page's own `guiding` list in web/src/components/Review.tsx, and diagramText() in
// src/diagram.ts. Pure: nothing here asks the desk.

// One step of the walk-through: what it's about, and where its sections start in the list.
struct WalkStep: Equatable, Sendable {
  let at: Int  // its first section in the list
  let title: String
  let body: String
  let check: String
  let note: String
  let diagram: String  // the id of its diagram in ai.diagrams, or ""
}

// The guided review's list: its steps' sections, then the ones outside them that carry a potential bug.
struct Guided: Sendable {
  let list: [DiffSection]
  let steps: [WalkStep]
  let beyond: Int  // from here on, potential bugs outside the guide
  let left: Int  // files changed that the guide doesn't show
}

extension Diff {
  // A file's neighbouring hunks at one level and for one reason, as one section.
  static func grouped(_ hunks: [ReviewHunk], into list: inout [DiffSection]) {
    let from = list.count
    for h in hunks {
      if list.count > from, let last = list.last, last.path == (h.path ?? ""), last.level == h.level, last.why == h.why {
        list[list.count - 1] = section(last.key, last.path, last.file, level: last.level, why: last.why, last.hunks + [h])
      } else {
        list.append(section(h.id, h.path ?? "", h.file ?? 0, level: h.level, why: h.why, [h]))
      }
    }
  }

  // The walk-through as one list of sections: each step's, then from `beyond` on what no step covers, then from `rest`
  // on the desk's fold.
  static func walk(_ o: ReviewOrder) -> (list: [DiffSection], rest: Int, steps: [WalkStep], beyond: Int) {
    var list: [DiffSection] = []
    let steps = (o.steps ?? []).map { st in
      let at = list.count
      grouped(st.hunks, into: &list)
      return WalkStep(at: at, title: st.title ?? "", body: st.body ?? "", check: st.check ?? "", note: st.note ?? "", diagram: st.diagram ?? "")
    }
    let beyond = list.count
    grouped(o.beyond ?? [], into: &list)
    return (list + restOf(o), list.count, steps, beyond)
  }

  // What the guided review shows: only its steps, so the guide holds your attention; a potential bug the steps leave out
  // (one of the first `bugs` notes) still shows, after them. The rest is left to Traditional.
  static func guided(_ o: ReviewOrder, bugs: Int) -> Guided {
    let w = walk(o)
    let after = w.list.dropFirst(w.beyond)
    let flagged = after.filter { s in s.notes.contains { $0 < bugs } }
    let left = Set(after.filter { s in !flagged.contains { $0.key == s.key } }.map(\.path)).count
    return Guided(list: Array(w.list.prefix(w.beyond)) + flagged, steps: w.steps, beyond: w.beyond, left: left)
  }

  // A test file: the guided review folds it until you open it, so the change itself gets the attention.
  static func isTestPath(_ p: String) -> Bool {
    let name = p.split(separator: "/").last.map(String.init) ?? ""
    return p.range(of: #"(^|/)(tests?|__tests__|specs?|testing)/"#, options: [.regularExpression, .caseInsensitive]) != nil
      || name.range(of: #"([._-](test|spec)s?|^test_[^/]*)\.[a-z0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
  }

  // A section's notes (indices into ai.notes): those on one of its lines, and those about the whole file, which sit
  // above its diff. A note with line 0, or on a line no hunk here has, is the file's.
  static func placed(_ s: DiffSection, _ notes: [AiReview.Note]) -> (file: [Int], lines: [Int]) {
    var file: [Int] = []
    var lines: [Int] = []
    for n in s.notes where notes.indices.contains(n) {
      if onLines(s.hunks, line: notes[n].line ?? 0, side: notes[n].side ?? "new") { lines.append(n) } else { file.append(n) }
    }
    return (file, lines)
  }

  // Whether something on `line` of one side is on this line of the diff: an unchanged line is on both sides.
  static func on(_ l: PatchLine, line: Int, side: String) -> Bool {
    side == "old" ? l.old == line && l.kind != .add && l.kind != .hunk : l.new == line && l.kind != .del && l.kind != .hunk
  }
}

// One plain line per edge or message ("fetchPr() → buildPrompt(): claims"): the window's own fallback when it can't lay
// a diagram out, and all the phone draws of one.
func diagramText(_ graph: DiagramGraph) -> [String] {
  switch graph {
  case .flow(let g):
    let byId = Dictionary(g.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let name = { (id: String) -> String in
      guard let n = byId[id] else { return id }
      let label = n.label ?? n.id
      return n.mark.map { "\(label) (\($0))" } ?? label
    }
    var lines = g.edges.map { e in
      "\(name(e.from ?? "")) \(e.style == "line" ? "—" : "→") \(name(e.to ?? ""))\((e.label ?? "").isEmpty ? "" : ": \(e.label ?? "")")"
    }
    let linked = Set(g.edges.flatMap { [$0.from ?? "", $0.to ?? ""] })
    for n in g.nodes where !linked.contains(n.id) { lines.append(name(n.id)) }
    return lines
  case .sequence(let g):
    let label = Dictionary(g.participants.map { ($0.id, $0.label ?? $0.id) }, uniquingKeysWith: { a, _ in a })
    let name = { (id: String) in label[id] ?? id }
    var lines: [String] = []
    func notesAt(_ i: Int) {
      for note in g.notes where note.at == i { lines.append("Note over \((note.over ?? []).map(name).joined(separator: ", ")): \(note.text ?? "")") }
    }
    for (i, m) in g.messages.enumerated() {
      notesAt(i)
      lines.append("\(name(m.from ?? "")) → \(name(m.to ?? ""))\((m.text ?? "").isEmpty ? "" : ": \(m.text ?? "")")")
    }
    notesAt(g.messages.count)
    return lines
  case .other: return []
  }
}
