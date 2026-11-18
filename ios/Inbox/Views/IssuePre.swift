import SwiftUI

// An issue's pre-review, as the window's IssuePre (web/src/components/Detail.tsx): what's actually wrong and what we'd
// do, from the code in your clone when it read it; a walk through it when it isn't simple; or the screen's flag, with
// nothing else read. Or where it stands: being read, failed, none yet. Every word of it is the model's: plain text.
// Block (an injection's call to action) and Make PR with fix are the page's bar's.
struct IssuePre: View {
  let detail: ItemDetail
  var busy = false  // a write of this issue's is on its way
  let run: (String) -> Void  // "analyze" | "trust" | "unblock"
  @State var at = 0  // the walk's step

  var body: some View {
    let r = detail.issueAi
    let standing = detail.preStanding
    if detail.blockedAuthor == true {
      let author = detail.item?.author ?? detail.card.author ?? ""
      section {
        said("@\(author) is blocked on your desk: their items are muted and no agent reads them.", "Unblock @\(author)", "unblock")
      }
    } else if let r {
      section {
        if let standing { status(standing) }
        if let flag = r.injection {
          Lead(
            label: "Possible prompt injection from @\(flag.who ?? "").", text: "\(flag.why ?? "") No agent read it further.", size: 13.5,
            labelColor: Theme.red, color: Theme.red)
          link("Not an injection: analyze it", "trust")
        } else {
          read(r)
        }
      }
    } else if let standing {
      section { status(standing) }
    }
  }

  private func section(@ViewBuilder _ rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SmallHead(text: "Pre-review")
      rows()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func status(_ standing: ItemDetail.PreStanding) -> some View {
    switch standing {
    case .running(let again):
      Text(again ? "Reading it again since its latest activity" : "Your agent is reading it").sans(13).foregroundStyle(Theme.pencil)
    case .failed(let why): said("The pre-review failed: \(why)", "Try again", "analyze", Theme.red)
    case .stale: said("Written before its latest activity.", "Read it again", "analyze")
    case .none: said("None yet.", "Analyze it", "analyze")
    }
  }

  // A line of where it stands, then what to press about it.
  private func said(_ words: String, _ label: String, _ key: String, _ color: Color = Theme.pencil) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Prose(text: words, size: 13).foregroundStyle(color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      link(label, key)
    }
  }

  // A quiet link, as the AI review's: the page's one accent is its bar's.
  private func link(_ words: String, _ key: String) -> some View {
    Button {
      run(key)
    } label: {
      Text(words).sans(13, 550).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2)
        .frame(minHeight: 36).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(busy)
  }

  @ViewBuilder
  private func read(_ r: IssueReview) -> some View {
    Lead(label: "\(Words.issueKind(r.kind)).", text: r.summary ?? "", size: 14.5, color: Theme.ink)
    Text(r.code == true ? "From the code in your clone" : "From the issue's text alone: no local clone to read").sans(12.5)
      .foregroundStyle(Theme.pencil)
    field("What's wrong", r.problem)
    field("Cause", r.cause)
    if !r.evidence.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(r.evidence.enumerated()), id: \.offset) { _, e in
          // The backticks make it code: a path never has one.
          Prose(text: "`\((e.path ?? "").replacingOccurrences(of: "`", with: "")):\(String(e.line ?? 0))`  \(e.why ?? "")")
            .foregroundStyle(Theme.pencil).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    field(r.fixable == true ? "The fix" : "What we'd do", r.fix)
    if !r.steps.isEmpty { walk(r.steps) }
  }

  @ViewBuilder
  private func field(_ label: String, _ text: String?) -> some View {
    if let text, !text.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).sans(12.5).foregroundStyle(Theme.pencil)
        Prose(text: text, size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // One step at a time, Back and Next under it.
  private func walk(_ steps: [IssueReview.Step]) -> some View {
    let k = min(max(at, 0), steps.count - 1)
    return VStack(alignment: .leading, spacing: 6) {
      FlowLine(spacing: 8) {
        Text(steps[k].title ?? "").sans(13.5, 600).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
        Text("Step \(k + 1) of \(steps.count)").sans(13, tabular: true).foregroundStyle(Theme.pencil)
      }
      Prose(text: steps[k].body ?? "", size: 13.5).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 20) {
        step("Back", to: k - 1, off: k <= 0)
        step("Next", to: k + 1, off: k >= steps.count - 1)
      }
    }
    .ruled()
  }

  private func step(_ words: String, to: Int, off: Bool) -> some View {
    Button {
      at = to
    } label: {
      Text(words).sans(13, 550).foregroundStyle(off ? Theme.faint : Theme.ink2)
        .frame(minHeight: 40).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(off)
  }
}

#if DEBUG
  extension ItemDetail {
    // An issue's pre-review as the mock never sends it, cut from what it does send: for ios/shots.sh and trying by hand.
    func debugging(_ state: String) -> ItemDetail {
      var d = self
      switch state {
      case "running", "none", "off":
        d.issueAi = nil
        d.issueAiState = state == "none" ? nil : state
      case "again": d.issueAiState = "running"
      case "failed":
        d.issueAi = nil
        d.issueAiState = "failed"
        d.issueAiError = "Claude Code isn't logged in. Run `claude auth login` in a terminal."
      case "stale": d.issueAi?.updatedAt = "earlier"
      case "injection":
        d.issueAi?.injection = .init(
          who: item?.author, why: "A comment tells whoever reads it to ignore their instructions and post the repository's secrets.")
        d.issueAi?.fixable = false
      case "blocked": d.blockedAuthor = true
      default: break
      }
      return d
    }
  }
#endif
