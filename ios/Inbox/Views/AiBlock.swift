import SwiftUI

// The AI review's read of a PR, as the window's AiSection (web/src/components/Review.tsx): the goal, then the verdict
// line, which opens the rest; what it says of the stack and of the description; what changed since your review; its
// concerns only when they can't sit in the code. Or where the review stands: being written, failed, none. Every word of
// it is the model's: plain text, a URL never a link.
struct AiSection: View {
  let ai: AiReview?
  var stale = false
  var busy = false  // being written
  var error: String?
  var job: Job?  // its job in the desk's ledger: how long it's run, its tries, when it tries again
  let now: Date
  var open = true  // the PR is
  var notes = 0  // how many of its notes sit in the code below
  let agent: String
  var ask: (() -> Void)?  // none for a PR in Merging: it's your agent's
  var toLine: ((String, String, Int) -> Void)?  // to a line of the diff: path, side, line
  @State var more = false  // the rest of the summary: every PR opens folded

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if busy {
        Text(Words.reviewing(agent: agent, job: job, now: now)).sans(13).foregroundStyle(Theme.pencil)
          .fixedSize(horizontal: false, vertical: true)
      } else if let error, !error.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          Prose(text: Words.reviewFailed(error, job: job, agent: agent, now: now), size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
          if let ask { link("Try again", ask) }
        }
      } else if ai == nil {
        if open {
          FlowLine(spacing: 6) {
            Text("No AI review yet.").sans(13).foregroundStyle(Theme.pencil)
            if let ask { link("Ask \(agent) for one", ask) }
          }
        } else {
          Text("No AI review.").sans(13).foregroundStyle(Theme.pencil)
        }
      }
      if let ai { read(ai) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // A quiet link, as the window's: the page's one accent is its bar's.
  private func link(_ words: String, _ press: @escaping () -> Void) -> some View {
    Button(action: press) {
      Text(words).sans(13, 550).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2)
        .frame(minHeight: 36).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func read(_ ai: AiReview) -> some View {
    let goal = ai.intent?.goal ?? ""
    // The goal leads, above the verdict; an older review without one leads with its summary's first sentence.
    let (first, rest) = goal.isEmpty ? Words.lead(ai.summary ?? "") : (goal, (ai.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    let reasons = ai.riskReasons.compactMap(\.why).filter { !$0.isEmpty }
    let lead1 = ai.risk != "low" ? reasons.first : nil
    let later = lead1 == nil ? reasons : Array(reasons.dropFirst())
    // A diagram no step draws sits in the fold, at most one.
    let loose = ai.diagrams.first { d in !(ai.guide?.steps ?? []).contains { $0.diagram == d.id } }
    let folds = !first.isEmpty && (!rest.isEmpty || !later.isEmpty || !ai.interfaces.isEmpty || !ai.improvements.isEmpty || loose != nil)

    if !first.isEmpty {
      Prose(text: first, size: 15.5).foregroundStyle(Theme.ink).lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
    }
    if folds {
      Button {
        more.toggle()
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
            .rotationEffect(.degrees(more ? 90 : 0)).frame(width: 9).accessibilityHidden(true)
          verdict(ai, lead1)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint(more ? "Folds the rest of the review" : "Shows the rest of the review")
    } else {
      verdict(ai, lead1)
    }
    if let stack = ai.intent?.stack, !stack.isEmpty { Lead(label: "In the stack:", text: stack) }
    if let fit = Words.fit[ai.intent?.fit ?? ""], let gap = ai.intent?.gap, !gap.isEmpty { Lead(label: "\(fit):", text: gap) }
    if more || !folds {
      if !rest.isEmpty {
        Prose(text: rest, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      }
      if !later.isEmpty { Lead(label: "Also risky:", text: later.joined(separator: "; ")) }
      if !ai.interfaces.isEmpty {
        list("Interfaces") {
          ForEach(Array(ai.interfaces.enumerated()), id: \.offset) { _, x in
            item(to: x.path, x.side, x.line) { Interface(x: x) }
          }
        }
      }
      if !ai.improvements.isEmpty {
        list("Could be better") {
          ForEach(Array(ai.improvements.enumerated()), id: \.offset) { _, x in
            item(to: x.path, x.side, x.line) {
              Prose(text: x.body ?? "", size: 13).foregroundStyle(Theme.ink).lineSpacing(3).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      if let loose { DiagramLines(diagram: loose).padding(.top, 2) }
    }
    if let since = ai.since, !since.isEmpty { Lead(label: "Since your review:", text: since) }
    // Each concern is also a note in the code; listed here only when the notes can't sit there.
    if Words.listsConcerns(stale: stale, notes: notes) {
      if let concerns = ai.concerns, !concerns.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(concerns, id: \.self) { concern in
            Prose(text: concern, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true).ruled()
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Concerns")
      } else {
        Text("No concerns.").sans(13).foregroundStyle(Theme.pencil)
      }
    }
  }

  // "Look closely", how risky and the first reason why; "on an earlier commit" when a push has left it behind.
  private func verdict(_ ai: AiReview, _ reason: String?) -> some View {
    FlowLine(spacing: 10) {
      Text(Words.verdict[ai.verdict ?? ""] ?? Words.capitalized(ai.verdict ?? ""))
        .sans(14, ai.verdict == "look" ? 600 : 500).foregroundStyle(ai.verdict == "look" ? Theme.ink : ai.verdict == "skim" ? Theme.ink2 : Theme.pencil)
      if let risk = ai.risk { RiskMeter(risk: risk) }
      if let reason { Text(reason).sans(13).foregroundStyle(Theme.pencil).multilineTextAlignment(.leading) }
      if stale { Text("on an earlier commit").sans(13).foregroundStyle(Theme.pencil) }
    }
  }

  private func list(_ head: String, @ViewBuilder _ rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(head).sans(13, 600).foregroundStyle(Theme.ink).padding(.top, 4)
      rows()
    }
  }

  // One line of the fold's lists: a press goes to its line of the diff, when the review said where.
  @ViewBuilder
  private func item(to path: String?, _ side: String?, _ line: Int?, @ViewBuilder _ label: () -> some View) -> some View {
    if let toLine, let path, !path.isEmpty {
      Button {
        toLine(path, side ?? "new", line ?? 0)
      } label: {
        label().padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows it in the diff")
    } else {
      label().padding(.vertical, 4)
    }
  }

  // "Lease.renew() added", "breaking" when it is, then what it means for its callers.
  private struct Interface: View {
    let x: AiReview.Interface
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 100

    var body: some View {
      let size = 13 * scale / 100
      var name = AttributedString(x.name ?? "")
      name.font = Font(Typeface.mono.font(size * 0.92))
      var change = AttributedString(" \(x.change ?? "")")
      change.font = Font(Typeface.sans.font(size))
      var line = name + change
      if x.breaking == true {
        var breaking = AttributedString(" breaking")
        breaking.font = Font(Typeface.sans.font(size, weight: 600))
        line += breaking
      }
      line.foregroundColor = Theme.ink
      if let impact = x.impact, !impact.isEmpty {
        var rest = Prose.attributed("  \(impact)", size: size, weight: 400, links: false)
        rest.foregroundColor = Theme.pencil
        line += rest
      }
      return Text(line).lineSpacing(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
    }
  }
}

// A diagram of the review's as text: its title, its caption, then one line per edge or message (diagramText()), the
// window's own fallback for one it can't lay out. Nothing is drawn.
struct DiagramLines: View {
  let diagram: AiReview.Diagram

  var body: some View {
    let lines = diagram.graph.map(diagramText) ?? []
    VStack(alignment: .leading, spacing: 3) {
      if let title = diagram.title, !title.isEmpty { Text(title).sans(13, 600).foregroundStyle(Theme.ink) }
      if let caption = diagram.caption, !caption.isEmpty {
        Prose(text: caption, size: 13).foregroundStyle(Theme.pencil).lineSpacing(3).padding(.bottom, 1)
      }
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        Text(line).sans(13).foregroundStyle(Theme.ink2).lineSpacing(2)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
