import SwiftUI

// A PR's State, as the window's sidebar says it: its checks, who reviews it, what stands in its merge's way and what it
// depends on, a line each, red or amber only where that's a problem. Checks and Reviewers open to each by name.
struct ReviewState: View {
  @Environment(Store.self) private var store
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var textSize
  let card: Card
  let review: ReviewView
  var addReviewers: (() -> Void)?  // on your open PR that's ready: + Add reviewers
  @State private var open: String?
  @State private var allChecks = false  // the passing ones shown too
  @State private var shards: Set<String> = []

  // Sorted away, done or resolved, its problems go grey (Review.tsx's calm()).
  private var dim: Bool { !card.active || card.resolved != nil || card.bucket == "hide" }
  private func tone(_ c: Color) -> Color { dim ? Theme.pencil : c }
  private var large: Bool { textSize.isAccessibilitySize }

  var body: some View {
    let reviewers = review.reviewers
    let deps = review.stack == nil ? ReviewState.depends(card) : ""
    VStack(alignment: .leading, spacing: 0) {
      SmallHead(text: "State")
      if let error = review.checksError {
        Text("Couldn't load the checks: \(error)").sans(13).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, 10)
        Theme.rule.frame(height: 1)
      }
      if let checks = review.checks {
        row("Checks", checks.line ?? "", checks.failing == true ? tone(Theme.red) : Theme.ink, opens: checks.list.isEmpty ? nil : "checks")
        if open == "checks" { checkList(checks) }
      }
      if let reviewers {
        let opens = !reviewers.list.isEmpty || addReviewers != nil
        row("Reviewers", reviewers.line ?? "", reviewers.changes == true ? tone(Theme.amber) : Theme.ink, opens: opens ? "reviewers" : nil)
        if open == "reviewers" { reviewerList(reviewers) }
      }
      if let merge = review.merge, !merge.isEmpty { row("Merge", merge, tone(Theme.amber)) }
      if !deps.isEmpty { row("Depends", deps, Theme.ink) }
    }
    #if DEBUG
      .task {
        if let part = store.debugPart {
          store.debugPart = nil
          open = part
        }
      }
    #endif
  }

  // Another PR it needs merged first, and the open PRs that need it (Review.tsx's depFacts()).
  static func depends(_ c: Card) -> String {
    var parts: [String] = []
    if let ref = c.blocker?.ref, !ref.isEmpty { parts.append("blocked by \(ref)") }
    if let blocks = c.blocks, !blocks.isEmpty { parts.append("blocks \(Words.andMore(blocks))") }
    return parts.joined(separator: " · ")
  }

  // One line of the table: its name, where it stands, and a chevron when it opens.
  @ViewBuilder
  private func row(_ name: String, _ line: String, _ color: Color, opens: String? = nil) -> some View {
    let on = opens != nil && open == opens
    let said = Text(line).sans(14, 550).foregroundStyle(color).lineLimit(on ? nil : 2).multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
    let label = HStack(alignment: .firstTextBaseline, spacing: 8) {
      // At an accessibility text size its name has no column to fit in: it goes above what it says.
      if large {
        VStack(alignment: .leading, spacing: 2) {
          Text(name).sans(13).foregroundStyle(Theme.pencil)
          said
        }
      } else {
        Text(name).sans(13).foregroundStyle(Theme.pencil).frame(width: 84, alignment: .leading)
        said
      }
      Spacer(minLength: 4)
      if opens != nil {
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
          .rotationEffect(.degrees(on ? 90 : 0)).accessibilityHidden(true)
      }
    }
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    if let opens {
      Button {
        open = on ? nil : opens
      } label: {
        label
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(name): \(line)")
      .accessibilityValue(on ? "open" : "closed")
    } else {
      label.accessibilityElement(children: .combine)
    }
    Theme.rule.frame(height: 1)
  }

  // MARK: Checks

  // A row each, shards of one check folded into one; past six rows the passing and skipped wait behind one line.
  @ViewBuilder
  private func checkList(_ checks: Checks) -> some View {
    let groups = CheckGroup.of(checks.list)
    let folds = groups.count > CheckGroup.rows
    let shown = folds && !allChecks ? groups.filter { !$0.dot.quiet } : groups
    let hidden = groups.count - shown.count
    VStack(alignment: .leading, spacing: 0) {
      ForEach(shown) { g in
        if g.checks.count == 1 {
          check(g.checks[0], g.name)
        } else {
          let on = shards.contains(g.name)
          Button {
            if on { shards.remove(g.name) } else { shards.insert(g.name) }
          } label: {
            listRow(dot: g.dot, name: g.name, state: "\(g.checks.count)", chevron: on ? 90 : 0)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(g.name): \(g.dot.words), \(g.checks.count) checks")
          if on {
            ForEach(Array(g.checks.enumerated()), id: \.offset) { _, c in
              let short = String((c.name ?? "").dropFirst(g.name.count)).trimmingCharacters(in: .whitespaces)
              check(c, short.isEmpty ? c.name ?? "" : short).padding(.leading, 16)
            }
          }
        }
      }
      if folds, hidden > 0 || allChecks {
        Button(allChecks ? "Show less" : "\(hidden) more passing") { allChecks.toggle() }
          .buttonStyle(.plain).sans(13).foregroundStyle(Theme.pencil)
          .frame(minHeight: 40, alignment: .leading).contentShape(Rectangle())
      }
    }
    .padding(.vertical, 2)
    Theme.rule.frame(height: 1)
  }

  // One check: its page opens where it has one.
  @ViewBuilder
  private func check(_ c: Checks.Check, _ label: String) -> some View {
    let dot = CheckDot(c)
    let line = listRow(dot: dot, name: label, state: dot == .green ? "" : dot.words)
      .accessibilityElement(children: .ignore).accessibilityLabel("\(c.name ?? label): \(dot.words)")
    if let url = c.url.flatMap(URL.init(string:)), url.scheme == "https" {
      Button {
        openURL(url)
      } label: {
        line
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens its page")
    } else {
      line
    }
  }

  private func listRow(dot: CheckDot, name: String, state: String, chevron: Double? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Dot(dot: dot, dim: dim).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
      Text(name).sans(13).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 6)
      // Red only in words: a group's count stays quiet beside its dot.
      if !state.isEmpty { Text(state).sans(13, tabular: true).foregroundStyle(dot == .red && chevron == nil ? tone(Theme.red) : Theme.pencil).fixedSize() }
      if let chevron {
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
          .rotationEffect(.degrees(chevron)).accessibilityHidden(true)
      }
    }
    .frame(minHeight: 36)
    .contentShape(Rectangle())
  }

  // How a check is doing, as the window's dot: red, a red ring where it isn't required, amber while it runs, green, grey.
  private struct Dot: View {
    let dot: CheckDot
    let dim: Bool

    var body: some View {
      let red = dim ? Theme.faint : Theme.red
      Group {
        switch dot {
        case .red: Circle().fill(red)
        case .amber: Circle().strokeBorder(red, lineWidth: 2)
        case .yellow: Circle().fill(dim ? Theme.faint : Theme.amber)
        case .green: Circle().fill(dim ? Theme.faint : Theme.green)
        case .grey: Circle().fill(Theme.ruleStrong)
        }
      }
      .frame(width: 8, height: 8)
      .accessibilityHidden(true)
    }
  }

  // MARK: Reviewers

  // Who holds it first, each with where they stand in words.
  @ViewBuilder
  private func reviewerList(_ reviewers: Standings) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(reviewers.list.enumerated()), id: \.offset) { _, r in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(r.who ?? "").sans(13).foregroundStyle(Theme.ink2).lineLimit(1)
          Spacer(minLength: 6)
          Text(r.state ?? "").sans(13).foregroundStyle(r.state == "changes requested" ? tone(Theme.amber) : Theme.pencil).fixedSize()
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
      }
      if let addReviewers {
        Button("+ Add reviewers", action: addReviewers)
          .buttonStyle(.plain).sans(13).foregroundStyle(Theme.pencil)
          .frame(minHeight: 40, alignment: .leading).contentShape(Rectangle())
      }
    }
    .padding(.vertical, 2)
    Theme.rule.frame(height: 1)
  }
}

// Under a PR's title: the reviewers with a verdict, a green tick for approved and "changes" in amber (HeadReviewers).
struct HeadReviewers: View {
  let list: [Standings.Standing]

  var body: some View {
    let shown = list.filter { $0.state == "approved" || $0.state == "changes requested" }
    if !shown.isEmpty {
      shown.enumerated().reduce(Text("reviewers").foregroundStyle(Theme.pencil)) { line, r in
        let approved = r.element.state == "approved"
        return line + Text(r.offset == 0 ? "  " : "  ·  ").foregroundStyle(Theme.faint) + Text(r.element.who ?? "").foregroundStyle(Theme.ink2)
          + Text(approved ? " ✓" : " changes").foregroundStyle(approved ? Theme.green : Theme.amber)
      }
      .sans(13)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel("Reviewers: " + shown.map { "\($0.who ?? "") \($0.state ?? "")" }.joined(separator: ", "))
    }
  }
}
