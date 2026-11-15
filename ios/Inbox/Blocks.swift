import Foundation

// Your agent's answer as blocks and spans, the twin of src/prose.ts's blocks() and inline(): paragraphs, lists, `code`,
// ``` blocks and **bold** read as meant. Text only: a URL stays the text it is, and a markdown link reads "label (url)",
// so a label never hides where it goes. Drawn by ProseBlocks (Views/Chat.swift) as Text, never HTML.

struct Span: Equatable, Sendable {
  var text: String
  var code = false
  var bold = false
}

enum Block: Equatable, Sendable {
  case p([Span])
  case ul([[Span]])
  case ol(start: Int, items: [[Span]])
  case pre(text: String, info: String)  // info: the fence's ```suggestion or ```ts, kept only for Copy
}

enum Blocks {
  private struct Raw {
    var kind: String  // "p" | "ul" | "ol" | "pre"
    var lines: [String] = []  // a paragraph's
    var items: [[String]] = []  // a list's, each its lines
    var start = 1
    var heading = false
    var info = ""
  }

  private static func prefix(_ line: String, _ pattern: String) -> Substring? {
    line.range(of: pattern, options: .regularExpression).map { line[$0] }
  }

  static func parse(_ text: String) -> [Block] {
    var raw: [Raw] = []
    var fence: [String]?
    var info = ""
    var open: Int?  // the open paragraph or list in `raw`, which a plain line continues
    let trim = { (s: String) in s.trimmingCharacters(in: .whitespaces) }
    let pre = { (lines: [String], info: String, raw: inout [Raw]) in
      if !lines.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { raw.append(Raw(kind: "pre", lines: lines, info: info)) }
    }
    let item = { (kind: String, rest: String, start: Int, raw: inout [Raw], open: inout Int?) in
      if let i = open, raw[i].kind == kind {
        raw[i].items.append([trim(rest)])
      } else {
        raw.append(Raw(kind: kind, items: [[trim(rest)]], start: start))
        open = raw.count - 1
      }
    }
    for line in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
      if fence != nil {
        if trim(line) != "```" {
          fence?.append(line)
        } else {
          pre(fence ?? [], info, &raw)
          fence = nil
        }
        continue
      }
      if trim(line).hasPrefix("```") {
        fence = []
        let rest = trim(String(trim(line).dropFirst(3)))
        info = rest.range(of: #"^[\w+-]{1,30}$"#, options: .regularExpression) != nil ? rest : ""
        open = nil
        continue
      }
      if trim(line).isEmpty {
        open = nil
        continue
      }
      if let h = prefix(line, #"^ {0,3}#{1,6}[ \t]"#) {
        raw.append(Raw(kind: "p", lines: [trim(String(line.dropFirst(h.count)))], heading: true))
        open = nil
        continue
      }
      if let b = prefix(line, #"^[ \t]*[-*][ \t]"#) {
        item("ul", String(line.dropFirst(b.count)), 1, &raw, &open)
        continue
      }
      if let n = prefix(line, #"^[ \t]*\d{1,3}\.[ \t]"#) {
        item("ol", String(line.dropFirst(n.count)), Int(n.filter(\.isNumber)) ?? 1, &raw, &open)
        continue
      }
      if let i = open {
        if raw[i].kind == "p" { raw[i].lines.append(trim(line)) } else { raw[i].items[raw[i].items.count - 1].append(trim(line)) }
      } else {
        raw.append(Raw(kind: "p", lines: [trim(line)]))
        open = raw.count - 1
      }
    }
    if let fence { pre(fence, info, &raw) }
    return raw.compactMap { r in
      switch r.kind {
      case "pre": return .pre(text: r.lines.joined(separator: "\n"), info: r.info)
      case "ul": return .ul(r.items.map { inline($0.joined(separator: "\n")) })
      case "ol": return .ol(start: r.start, items: r.items.map { inline($0.joined(separator: "\n")) })
      default:
        let spans = inline(r.lines.joined(separator: "\n"), heading: r.heading)
        return spans.isEmpty ? nil : .p(spans)
      }
    }
  }

  // A line's spans: `code` between backticks, **bold** between pairs of stars (an unpaired one of either is text).
  static func inline(_ text: String, heading: Bool = false) -> [Span] {
    var parts = text.components(separatedBy: "`")
    // An odd backtick count leaves the last one unpaired: it's text.
    if parts.count % 2 == 0 { parts.replaceSubrange((parts.count - 2)..., with: [parts.suffix(2).joined(separator: "`")]) }
    let marks = parts.enumerated().reduce(0) { n, p in p.offset % 2 == 1 ? n : n + p.element.components(separatedBy: "**").count - 1 }
    var toggles = marks - marks % 2
    var out: [Span] = []
    var bold = false
    var run = ""
    for (i, part) in parts.enumerated() {
      if i % 2 == 1 {
        out.append(Span(text: unlinked(run), bold: bold))
        run = ""
        out.append(Span(text: part, code: true, bold: bold))
        continue
      }
      for (j, bit) in part.components(separatedBy: "**").enumerated() {
        if j > 0, toggles > 0 {
          out.append(Span(text: unlinked(run), bold: bold))
          run = ""
          toggles -= 1
          bold.toggle()
        } else if j > 0 {
          run += "**"
        }
        run += bit
      }
    }
    out.append(Span(text: unlinked(run), bold: bold))
    // Tidied: nothing empty, and neighbours of one kind are one span.
    var tidy: [Span] = []
    for var s in out where !s.text.isEmpty {
      if heading { s.bold = true }
      if let last = tidy.last, !s.code, !last.code, last.bold == s.bold { tidy[tidy.count - 1].text += s.text } else { tidy.append(s) }
    }
    return tidy
  }

  // A markdown link as its label and where it goes: "[the PR](https://…)" reads "the PR (https://…)".
  static func unlinked(_ text: String) -> String {
    text.replacingOccurrences(of: #"\[([^\]\n]{1,200})\]\((https://[^\s)]+)\)"#, with: "$1 ($2)", options: .regularExpression)
  }

  // Copy's text: a fence longer than any backtick run opening a line inside, since GitHub ends a block on one as long.
  static func fencedCopy(_ text: String, info: String) -> String {
    let runs = text.components(separatedBy: "\n").compactMap { prefix($0, #"^ {0,3}`+"#)?.filter { $0 == "`" }.count }
    let fence = String(repeating: "`", count: max(3, (runs.max() ?? 0) + 1))
    return "\(fence)\(info)\n\(text)\n\(fence)"
  }
}
