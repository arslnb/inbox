import SwiftUI

// The Conversation tab, in the diff's place, as the window's Conversation.tsx: a card each, those waiting on you first and
// edged in the accent, every comment unfolded with who, when and where, your agent's read of one waiting on you, and a
// row to reply in (the reply sheet). A resolved one nobody waits on you for is one line until pressed. Your comment on
// the PR closes it.
struct ConversationTab: View {
  @Environment(Store.self) private var store
  let review: ReviewView
  let waiting: [Conversation]  // less the ones answered from this page
  var answered: Set<String> = []  // answered from this page, until the review read again says so
  var sent: [SentWords] = []
  var reply: ((Conversation) -> Void)?  // nil: not open, so nothing takes a reply
  var ask: ((Conversation) -> Void)?  // nil: your agent is off
  var comment: (() -> Void)?  // your comment on the PR: an open one's
  var ref = ""
  @State private var shown: Set<String> = []  // resolved ones opened

  var body: some View {
    let ids = Set(waiting.map(\.id))
    let list = waiting + review.conversation.filter { !ids.contains($0.id) }
    VStack(alignment: .leading, spacing: 12) {
      if let error = review.conversationError {
        Text("Couldn't load what reviewers said: \(error)").sans(13).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
      } else if list.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("No conversation yet").sans(14, 550).foregroundStyle(Theme.ink2)
          Text("Comments and review threads on this PR show here.").sans(13).foregroundStyle(Theme.pencil)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
      }
      if !waiting.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          SmallHead(text: "Waiting on your reply")
          Text(String(waiting.count)).sans(12.5, tabular: true).foregroundStyle(Theme.faint)
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, -6)
      }
      ForEach(list) { c in
        if c.resolved == true, !ids.contains(c.id), !shown.contains(c.id) { resolved(c) } else { card(c, waits: ids.contains(c.id)) }
      }
      if let comment {
        compose(face: store.me, "Comment on \(ref)\u{2026}", comment).box(edge: Theme.rule)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // Who, where, "resolved" and how it began, on one line; pressed, the whole card.
  private func resolved(_ c: Conversation) -> some View {
    let first = c.comments.first
    return Button {
      shown.insert(c.id)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        WhoLine(who: first?.author ?? "", bot: first?.bot == true, rest: [c.path == nil ? "" : Words.place(c), "resolved"])
        Text(Blocks.saidLine(first?.body ?? "")).sans(13).foregroundStyle(Theme.pencil).lineLimit(1)
      }
      .padding(.horizontal, 12).padding(.vertical, 8)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .box(edge: Theme.rule)
    .accessibilityHint("Shows this resolved conversation")
  }

  private func card(_ c: Conversation, waits: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(c.comments.enumerated()), id: \.element.id) { i, m in
        if i > 0 { Theme.rule.frame(height: 1) }
        VStack(alignment: .leading, spacing: 4) {
          WhoLine(who: m.author ?? "", bot: m.bot == true, parts: who(c, i, m))
          SaidText(said: Blocks.said(m.body ?? ""))
        }
        .padding(12)
      }
      let mine = sent.filter { $0.thread == c.id }
      if !mine.isEmpty {
        VStack(alignment: .leading, spacing: 6) { ForEach(mine) { s in YoursSent(words: s) } }.padding(.horizontal, 12).padding(.bottom, 10)
      }
      if waits { take(c).padding(.horizontal, 12).padding(.bottom, 4) }
      FlowLine(spacing: 18) {
        if answered.contains(c.id) { Text("Reply sent.").foregroundStyle(Theme.pencil).frame(minHeight: 36) }
        if let url = c.url.flatMap(URL.init(string:)) { Link(destination: url) { words("Open on GitHub") } }
        if let ask { Button { ask(c) } label: { words("Ask your agent") }.buttonStyle(.plain) }
      }
      .sans(13, 550).foregroundStyle(Theme.ink2)
      .padding(.horizontal, 12)
      if let reply {
        Theme.rule.frame(height: 1)
        compose(face: store.me, Words.replyTo("Reply", c, me: store.me) + "\u{2026}") { reply(c) }
      }
    }
    .box(edge: waits ? Theme.accent : Theme.rule)
  }

  // A comment's when; on the first, where, "resolved", and a review's verdict in its colour.
  private func who(_ c: Conversation, _ i: Int, _ m: Conversation.Comment) -> [Dotted.Part] {
    var out: [Dotted.Part] = [.init(Words.age(m.at, now: store.now))]
    guard i == 0 else { return out }
    if c.path != nil { out.append(.init(Words.place(c))) }
    if c.resolved == true { out.append(.init("resolved")) }
    if c.state == "approved" { out.append(.init("Approved", Theme.green)) }
    if c.state == "changes_requested" { out.append(.init("Changes requested", Theme.amber)) }
    return out
  }

  // Your agent's read of one waiting on you: its call in semibold, then why.
  @ViewBuilder
  private func take(_ c: Conversation) -> some View {
    if let take = c.take?.take, !take.isEmpty {
      let (call, why) = Words.takeSplit(take)
      if let call {
        Lead(label: call + ":", text: why, size: 13.5)
      } else {
        Prose(text: why, size: 13.5).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      }
    } else if c.take == nil {
      if review.reading == true { Text("\(store.agent) is reading it.").sans(13).foregroundStyle(Theme.pencil) }
      if let error = review.readingError {
        Text("\(store.agent) couldn't read it: \(error)").sans(13.5).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func words(_ says: String) -> some View {
    Text(says).underline(color: Theme.ruleStrong).fixedSize().frame(minHeight: 36).contentShape(Rectangle().inset(by: -8))
  }

  // A row to write in, as the window's box: your picture and what it's for; a press opens the sheet you write in.
  private func compose(face: String, _ label: String, _ press: @escaping () -> Void) -> some View {
    Button(action: press) {
      HStack(alignment: .center, spacing: 8) {
        if !face.isEmpty { Avatar(login: face, size: 18) }
        Text(label).sans(13.5).foregroundStyle(Theme.pencil).lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

extension View {
  // A conversation's card on the sheet: a hairline round it, in the accent when it waits on you.
  fileprivate func box(edge: Color) -> some View {
    frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(edge, lineWidth: 1))
  }
}
