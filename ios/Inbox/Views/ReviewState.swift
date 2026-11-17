import SwiftUI

// A PR's State, as the window's sidebar says it: its Status (the AI review's risk, the checks, how big the change is),
// who reviews it, what stands in its merge's way and what it depends on, a line each, red or amber only where that's a
// problem. Each Status row opens to what's behind it; Reviewers to each by name.
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
  private func tone(_ t: Status.Tone) -> Color { tone(t == .bad ? Theme.red : t == .warn ? Theme.amber : Theme.green) }
  private var large: Bool { textSize.isAccessibilitySize }

  var body: some View {
    let reviewers = review.reviewers
    let deps = review.stack == nil ? ReviewState.depends(card) : ""
    VStack(alignment: .leading, spacing: 0) {
      SmallHead(text: "Status")
      if let ai = review.ai, let risk = ai.risk, !risk.isEmpty {
        let reasons = ai.riskReasons.compactMap(\.why).filter { !$0.isEmpty }
        // The rows' signal, for risk alone: one red bar for high, two orange for medium, all four green for low.
        status("risk", Status.risk(risk), color: Theme.ink) { Signal(lit: Status.riskBars(risk), said: Status.risk(risk)) }
        if open == "risk" { bullets(reasons.isEmpty ? ["No reason given."] : reasons) }
      }
      if let checks = review.checks {
        let (said, t) = Status.checks(checks)
        let passing = checks.list.filter { $0.state == "passing" }.count
        status("checks", said, color: Theme.ink, opens: !checks.list.isEmpty) {
          (Text(String(passing)).foregroundStyle(tone(t)) + Text("/\(checks.list.count)").foregroundStyle(Theme.pencil))
            .accessibilityLabel("\(passing) of \(checks.list.count) passing")
        }
        if open == "checks" { checkList(checks) }
      } else if let error = review.checksError {
        status("checks", "Checks couldn't load", color: Theme.ink) { EmptyView() }
        if open == "checks" {
          Text(error).sans(13).foregroundStyle(tone(Theme.red)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
          Theme.rule.frame(height: 1)
        }
      }
      if let item = review.item, let files = item.changedFiles, files > 0 {
        let (add, del) = (item.additions ?? 0, item.deletions ?? 0)
        status("changes", Status.changes(add: add, del: del, files: files), color: Theme.ink) {
          (Text("+\(add)").foregroundStyle(Theme.green) + Text(" \u{2212}\(del)").foregroundStyle(Theme.red))
            .accessibilityLabel("\(add) lines added, \(del) removed")
        }
        if open == "changes" {
          bullets([Words.plural(files, "file") + " changed", Words.plural(add, "line") + " added", Words.plural(del, "line") + " removed"])
        }
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

  // One row of Status: what it says on the left, its measure on the right, a chevron; a press shows what's behind it.
  @ViewBuilder
  private func status(_ id: String, _ said: String, color: Color, opens: Bool = true, @ViewBuilder end: () -> some View) -> some View {
    let on = open == id
    Button {
      open = on ? nil : id
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(said).sans(14, 550).foregroundStyle(color).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        end().sans(13, 500, tabular: true).fixedSize()
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
          .rotationEffect(.degrees(on ? 90 : 0)).opacity(opens ? 1 : 0).accessibilityHidden(true)
      }
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!opens)
    .accessibilityElement(children: .combine)
    .accessibilityValue(opens ? (on ? "open" : "closed") : "")
    // Opened, the rule goes under what it opens to.
    if !on { Theme.rule.frame(height: 1) }
  }

  // What a Status row opens to: its reasons, or its counts, a bullet each.
  private func bullets(_ lines: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\u{2022}").foregroundStyle(Theme.faint)
          Text(line).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .sans(13)
      }
    }
    .padding(.leading, 2)
    .padding(.bottom, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
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

  // Who holds it first, each with their picture and where they stand in words. On your open PR each person has one
  // action, as the window's icon: Remove one asked who hasn't reviewed, Ask again one who has. A team's ask is the team's.
  @ViewBuilder
  private func reviewerList(_ reviewers: Standings) -> some View {
    let yours = card.mine && review.item?.state == "open"
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(reviewers.list.enumerated()), id: \.offset) { _, r in
        let who = r.who ?? ""
        let act = yours ? Status.reviewerAct(who: who, state: r.state, draft: review.item?.draft == true) : nil
        HStack(alignment: .center, spacing: 0) {
          HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let face = Status.face(who, me: store.me) { Avatar(login: face) }
            Text(who).sans(13).foregroundStyle(Theme.ink2).lineLimit(1)
            Spacer(minLength: 14)
            Text(r.state ?? "").sans(13).foregroundStyle(r.state == "changes requested" ? tone(Theme.amber) : Theme.pencil).fixedSize()
          }
          .accessibilityElement(children: .combine)
          if let act {
            Button {
              Task { await store.reviewer(card, login: who, act: act) }
            } label: {
              Image(systemName: act == "remove" ? "xmark" : "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.pencil).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.busy(card.id))
            .accessibilityLabel(Status.reviewerLabel(act, who))
            .padding(.trailing, -12)
          }
        }
        .frame(minHeight: act == nil ? 36 : 44)
        .contextMenu {
          if let act { Button(Status.reviewerLabel(act, who)) { Task { await store.reviewer(card, login: who, act: act) } } }
        }
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

// Status's words, the window's own (Review.tsx's checksState(), changesWord() and StatusPart), and the reviewers' actions.
enum Status {
  enum Tone { case good, warn, bad }

  // A required check failing is red; an optional one failing, one cancelled or one still running is amber.
  static func checks(_ c: Checks) -> (said: String, tone: Tone) {
    if c.failing == true { return ("Checks failing", .bad) }
    if c.list.contains(where: { $0.state == "failing" || $0.state == "cancelled" }) { return ("Some checks failing", .warn) }
    if c.list.contains(where: { $0.state == "running" }) { return ("Checks running", .warn) }
    return ("Checks passing", .good)
  }

  // How big it is in a word, by its lines changed and its files.
  static func changes(add: Int, del: Int, files: Int?) -> String {
    let (lines, n) = (add + del, files ?? 0)
    if lines <= 100 && n <= 5 { return "Small changes" }
    if lines <= 600 && n <= 20 { return "Moderate changes" }
    return "Lots of changes"
  }

  static func risk(_ r: String) -> String { Words.capitalized(r) + " risk" }
  static func riskBars(_ r: String) -> Int { r == "high" ? 1 : r == "medium" ? 2 : 4 }  // RowIcons.tsx's RISK_BARS

  // Whose picture: a person's, yours too; none for a team.
  static func face(_ who: String, me: String) -> String? {
    who == "you" ? (me.isEmpty ? nil : me) : who.isEmpty || who.hasPrefix("@") ? nil : who
  }

  // "remove" for one asked who hasn't reviewed yet, "rerequest" for one who has (not on a draft); none for you or a team.
  static func reviewerAct(who: String, state: String?, draft: Bool) -> String? {
    guard who != "you", !who.isEmpty, !who.hasPrefix("@") else { return nil }
    if state == "asked" { return "remove" }
    return draft ? nil : "rerequest"
  }

  static func reviewerLabel(_ act: String, _ who: String) -> String {
    act == "remove" ? "Remove \(who) as a reviewer" : "Ask \(who) to review again"
  }
}

// Under a PR's title: the reviewers with a verdict, a green tick for approved and "changes" in amber (HeadReviewers).
struct HeadReviewers: View {
  @Environment(Store.self) private var store
  let list: [Standings.Standing]

  var body: some View {
    let shown = list.filter { $0.state == "approved" || $0.state == "changes requested" }
    if !shown.isEmpty {
      // Each with their picture, as the window's head.
      Dotted(
        parts: shown.enumerated().map { i, r in
          let approved = r.state == "approved"
          return .init(
            r.who ?? "", Theme.ink2, lead: i == 0 ? "reviewers" : nil, face: Status.face(r.who ?? "", me: store.me),
            mark: Text(approved ? " ✓" : " changes").foregroundStyle(approved ? Theme.green : Theme.amber))
        }
      )
      .sans(13)
      .accessibilityLabel("Reviewers: " + shown.map { "\($0.who ?? "") \($0.state ?? "")" }.joined(separator: ", "))
    }
  }
}
