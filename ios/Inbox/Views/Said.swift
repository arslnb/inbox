import SwiftUI

// What reviewers said on a PR, as the window's Conversation.tsx: each conversation waiting on you with your agent's read
// of it first, its own words under a fold, and Reply; the rest under one line. The comments and their actions are drawn
// once, here, for the page and for a thread under its line of the diff.

// Who, then where and when with a dot between: "azulus · src/sync/merge.ts:88 · 5h".
struct WhoLine: View {
  let who: String
  var bot = false
  var rest: [String] = []
  @Environment(Store.self) private var store

  var body: some View {
    // A person's picture before the name; a bot has none, as in the window, and nor do you.
    let face = !bot && !who.isEmpty && who.lowercased() != store.me.lowercased() ? who : nil
    Dotted(parts: [.init(who, Theme.ink2, face: face, strong: 12.5)] + rest.map { .init($0) }).sans(12.5)
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
          Prose(text: Words.saidText(m.body), size: 13.5, links: true)
            .foregroundStyle(Theme.ink).tint(Theme.ink2).lineSpacing(3).lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      ForEach(mine) { s in YoursSent(words: s) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

struct WhatWasSaid: View {
  @Environment(Store.self) private var store
  let review: ReviewView
  let waiting: [Conversation]  // less the ones answered from this page
  var answered: [Conversation] = []  // answered from this page, until the review read again says so
  var sent: [SentWords] = []
  var reply: ((Conversation) -> Void)?  // nil: not open, so nothing takes a reply
  var ask: ((Conversation) -> Void)?  // nil: your agent is off
  @State private var said: Set<String> = []  // whose own words are unfolded
  @State private var more = false
  @State private var opened: Set<String> = []  // of the ones not waiting on you

  var body: some View {
    let rest = review.conversation.filter { $0.waitingOnYou != true }
    VStack(alignment: .leading, spacing: 14) {
      if !waiting.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          SmallHead(text: "Waiting on your reply")
          Text(String(waiting.count)).sans(12.5, tabular: true).foregroundStyle(Theme.faint)
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, -6)
      }
      ForEach(waiting) { c in one(c) }
      ForEach(answered) { c in
        Text(Words.replyTo("Sent your reply", c, me: store.me) + ".").sans(13).foregroundStyle(Theme.pencil)
      }
      if !rest.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          Fold(
            label: "\(rest.count) \(waiting.isEmpty ? "" : "more ")\(rest.count == 1 ? "conversation" : "conversations") not waiting on you", open: more,
            tall: 44
          ) { more.toggle() }
          if more {
            VStack(alignment: .leading, spacing: 10) { ForEach(rest) { c in quiet(c) } }.padding(.bottom, 8)
          }
        }
        .padding(.vertical, -8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    #if DEBUG
      .task {
        if let want = store.debugSaid {
          store.debugSaid = nil
          if want == "more" {
            more = true
            if let first = rest.first { opened.insert(first.id) }
          } else if let first = waiting.first {
            said.insert(first.id)
          }
        }
      }
    #endif
  }

  private func mine(_ c: Conversation) -> [SentWords] { sent.filter { $0.thread == c.id } }

  // One waiting on you: who, where and when; what it comes to; your agent's take; their words under a fold; Reply.
  private func one(_ c: Conversation) -> some View {
    let last = c.comments.last
    let isOpen = said.contains(c.id)
    return VStack(alignment: .leading, spacing: 6) {
      WhoLine(who: last?.author ?? "", bot: last?.bot == true, rest: [Words.place(c), Words.age(last?.at, now: store.now)])
      Prose(text: Words.gist(c), size: 15).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
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
      VStack(alignment: .leading, spacing: 0) {
        Fold(label: Words.saidLabel(c), open: isOpen) { said.formSymmetricDifference([c.id]) }
        if isOpen { SaidComments(comments: c.comments, mine: mine(c)).padding(.top, 2).padding(.bottom, 4) }
        SaidActions(reply: reply.map { r in { r(c) } }, url: c.url, ask: ask.map { a in { a(c) } })
      }
      .padding(.vertical, -4)
    }
    .ruled()
  }

  // One nobody waits on you for, as a line; pressed, its words and what you can do with it.
  private func quiet(_ c: Conversation) -> some View {
    let isOpen = opened.contains(c.id)
    return VStack(alignment: .leading, spacing: 0) {
      Button {
        opened.formSymmetricDifference([c.id])
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          WhoLine(who: c.comments.first?.author ?? "", bot: c.comments.first?.bot == true, rest: [Words.place(c), c.resolved == true ? "resolved" : ""])
          if !isOpen {
            Prose(text: Words.firstLine(c.comments.last?.body), size: 13).foregroundStyle(Theme.ink2).lineSpacing(2).lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isOpen ? .isSelected : [])
      if isOpen {
        SaidComments(comments: c.comments, mine: mine(c))
        SaidActions(reply: reply.map { r in { r(c) } }, url: c.url, ask: ask.map { a in { a(c) } }).padding(.top, 2)
      }
    }
    .ruled()
  }
}

// A line that opens what's under it, in place: small and pencil, as "What azulus wrote" is in the window.
private struct Fold: View {
  let label: String
  let open: Bool
  var tall: CGFloat = 30
  let press: () -> Void

  var body: some View {
    Button(action: press) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
          .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 9)
          .accessibilityHidden(true)
        Text(label).sans(13).foregroundStyle(open ? Theme.ink2 : Theme.pencil).multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .frame(minHeight: tall)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(open ? .isSelected : [])
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
