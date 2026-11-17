import SwiftUI

// How what reviewers said is drawn, once, for the Conversation tab (ConversationTab.swift) and for a thread under its
// line of the diff: who, where and when, their words as the window's SaidText, and what you do with a conversation.

// Who, then where and when with a dot between: "azulus · src/sync/merge.ts:88 · 5h".
struct WhoLine: View {
  let who: String
  var bot = false
  var rest: [Dotted.Part] = []

  init(who: String, bot: Bool = false, rest: [String]) {
    self.init(who: who, bot: bot, parts: rest.map { .init($0) })
  }

  init(who: String, bot: Bool = false, parts: [Dotted.Part]) {
    self.who = who
    self.bot = bot
    rest = parts
  }

  var body: some View {
    // A person's picture before the name, yours too; a bot has none, as in the window.
    Dotted(parts: [.init(who, Theme.ink2, face: bot || who.isEmpty ? nil : who, strong: 12.5)] + rest).sans(12.5)
  }
}

// Yours from this page, until the conversation read again has it.
struct YoursSent: View {
  let words: SentWords
  var body: some View {
    Lead(label: "You · sent", text: words.body, color: Theme.ink)
  }
}

// The original words as GitHub has them, oldest first: who and how long ago, then what they wrote.
struct SaidComments: View {
  @Environment(Store.self) private var store
  let comments: [Conversation.Comment]
  var mine: [SentWords] = []
  var lines: Int?  // each one cut to this many, where there's little room (a sheet)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(comments) { m in
        VStack(alignment: .leading, spacing: 3) {
          WhoLine(who: m.author ?? "", bot: m.bot == true, rest: [Words.age(m.at, now: store.now)])
          // A reviewer's or a bot's words: a URL in them stays text, as the window's (docs/ui.md), never a link to follow.
          if let lines {
            Prose(text: Words.saidText(m.body), size: 13.5)
              .foregroundStyle(Theme.ink).lineSpacing(3).lineLimit(lines)
              .fixedSize(horizontal: false, vertical: true)
          } else {
            SaidText(said: Blocks.said(m.body ?? ""))
          }
        }
      }
      ForEach(mine) { s in YoursSent(words: s) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// What a reviewer wrote, as the window's SaidText: paragraphs, lists, a code block with its Copy, a <details> folded
// under its summary until pressed, <sub> as small print. Text only, never HTML: a link reads as its words, an image as
// its alt, underlined, and nothing opens from here; a long press offers Copy link.
struct SaidText: View {
  let said: [Said]
  @State private var open: Set<Int> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(said.enumerated()), id: \.offset) { i, s in
        switch s {
        case .block(let b): ProseBlocks(blocks: [b], size: 13.5).copiesLinks(SaidText.links(b))
        case .small(let spans): ProseBlocks(blocks: [.p(spans)], size: 12, color: Theme.pencil).copiesLinks(spans.filter { $0.link != nil })
        case .details(let summary, let blocks):
          VStack(alignment: .leading, spacing: 4) {
            Button {
              open.formSymmetricDifference([i])
            } label: {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.pencil)
                  .rotationEffect(.degrees(open.contains(i) ? 90 : 0)).frame(width: 9).accessibilityHidden(true)
                ProseBlocks(blocks: [.p(summary)], size: 13.5, color: Theme.ink2)
              }
              .frame(minHeight: 36)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open.contains(i) ? .isSelected : [])
            if open.contains(i) { SaidText(said: blocks).padding(.leading, 15) }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  static func links(_ b: Block) -> [Span] {
    switch b {
    case .p(let spans): spans.filter { $0.link != nil }
    case .ul(let items), .ol(_, let items): items.flatMap { $0.filter { $0.link != nil } }
    case .pre: []
    }
  }
}

extension View {
  // A long press copies a block's links; nothing opens one from the phone.
  @ViewBuilder
  func copiesLinks(_ spans: [Span]) -> some View {
    if spans.isEmpty {
      self
    } else {
      contextMenu {
        ForEach(Array(spans.enumerated()), id: \.offset) { _, s in
          Button(spans.count == 1 ? (s.image ? "Copy image link" : "Copy link") : "Copy link: \(s.text)") { UIPasteboard.general.string = s.link }
        }
      }
    }
  }
}

// What you do with one conversation: Reply (an open PR's) and its place on GitHub. There is no resolve from here.
struct SaidActions: View {
  var reply: (() -> Void)?
  var url: String?
  var ask: (() -> Void)?  // Ask your agent, about this conversation: your chat, on it

  // Each keeps its words whole and goes to the next line when they don't fit (large text); a touch reaches 8pt around
  // its words, 52pt tall, and stops short of the next one's.
  var body: some View {
    FlowLine(spacing: 18) {
      if let reply { Button(action: reply) { words("Reply") }.buttonStyle(.plain) }
      if let url = url.flatMap(URL.init(string:)) { Link(destination: url) { words("Open on GitHub") } }
      if let ask { Button(action: ask) { words("Ask your agent") }.buttonStyle(.plain) }
    }
    .sans(13, 550).foregroundStyle(Theme.ink2)
  }

  private func words(_ says: String) -> some View {
    Text(says).underline(color: Theme.ruleStrong).fixedSize().frame(minHeight: 36).contentShape(Rectangle().inset(by: -8))
  }
}

extension View {
  // A conversation's edge: a rule down its left, as the window's.
  func ruled() -> some View {
    padding(.leading, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) { Theme.ruleStrong.frame(width: 2) }
  }
}
