import SwiftUI
import UIKit

// What an opened page acts with: the bar at its foot (Back, its call to action, Done and Snooze, More) and the boxes
// that write (a sheet with a field and one named button).

// An opened page has no navigation bar, which would drop the swipe back from the left edge: this keeps it.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
  override open func viewDidLoad() {
    super.viewDidLoad()
    interactivePopGestureRecognizer?.delegate = self
  }

  public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    viewControllers.count > 1
  }
}

extension View {
  // An opened page: no bar above it, the paper under the status bar as its words scroll by.
  func openedPage() -> some View {
    background(Theme.paper)
      .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.paper, ignoresSafeAreaEdges: .top) }
      .toolbar(.hidden, for: .navigationBar)
  }
}

// The call to action: the one filled button on a page. `go`: the button that says yes (Approve, Hand off for merge),
// filled green as the window's `.act.primary.go`.
struct AccentAct: ButtonStyle {
  var go = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .sans(14, 600)
      .lineLimit(1)
      // Its words are never cut: where nothing more can fold away (the largest text), they draw a little smaller.
      .minimumScaleFactor(0.7)
      .foregroundStyle(go ? Theme.onGo : Theme.onAccent)
      .padding(.horizontal, 12)
      .frame(minHeight: 36)
      .background((go ? Theme.green : Theme.accent).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9))
      .opacity(enabled ? 1 : 0.45)
      .contentShape(Rectangle().inset(by: -4))
  }
}

// A quiet button beside the call to action; with options it's a menu of them (Snooze), groups parted by a line.
struct Quiet: Identifiable {
  let label: String
  var options: [[SnoozeOption]] = []
  let run: (SnoozeOption?) -> Void
  var id: String { label }
}

// The foot of an opened page, in the thumb's reach: Back, then More, the quiet buttons and the call to action. When
// they don't fit on one line (a long name, large text) the quiet ones fold into More, the last of `quiet` first; only
// when More alone still doesn't fit beside the call to action is it its three dots. Every button keeps its word while it can.
struct BottomBar<More: View>: View {
  @Environment(Store.self) private var store
  var cta: String?
  var go = false  // the call to action says yes: green
  var off = false
  var press: () -> Void = {}
  var quiet: [Quiet] = []
  var hasMore = false
  var done: String?  // in the call to action's place, quiet: what you did ("✓ You approved")
  @ViewBuilder var more: () -> More

  var body: some View {
    VStack(spacing: 0) {
      NoticeStack()
      ViewThatFits(in: .horizontal) {
        ForEach(0...quiet.count, id: \.self) { folded in line(folded, dots: false) }
        line(quiet.count, dots: true)
      }
      .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity)
      .background(Theme.paper)
      .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
    }
  }

  private func line(_ folded: Int, dots: Bool) -> some View {
    HStack(spacing: 6) {
      Button {
        if !store.path.isEmpty { store.path.removeLast() }
      } label: {
        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink2)
          .frame(width: 26, height: 44, alignment: .leading)
          .contentShape(Rectangle().inset(by: -14))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Back")
      Spacer(minLength: 0)
      if hasMore || folded > 0 {
        Menu {
          ForEach(quiet.suffix(folded).reversed()) { q in item(q) }
          if folded > 0, hasMore { Divider() }
          more()
        } label: {
          if dots { Image(systemName: "ellipsis").accessibilityLabel("More") } else { Text("More") }
        }
        .menuOrder(.fixed)
        .buttonStyle(PlainAct())
      }
      ForEach(quiet.dropLast(folded).reversed()) { q in item(q).buttonStyle(PlainAct()) }
      if let done { Text(done).sans(14, 550).foregroundStyle(Theme.pencil).lineLimit(1).fixedSize().padding(.leading, 4) }
      if let cta { Button(cta, action: press).buttonStyle(AccentAct(go: go)).disabled(off) }
    }
  }

  @ViewBuilder
  private func item(_ q: Quiet) -> some View {
    if q.options.isEmpty {
      Button(q.label) { q.run(nil) }
    } else {
      Menu {
        ForEach(Array(q.options.enumerated()), id: \.offset) { i, group in
          if i > 0, !group.isEmpty { Divider() }
          ForEach(group) { option in Button(option.label) { q.run(option) } }
        }
      } label: {
        Text(q.label)
      }
      .menuOrder(.fixed)
    }
  }
}

extension BottomBar where More == EmptyView {
  init(cta: String? = nil, off: Bool = false, press: @escaping () -> Void = {}, quiet: [Quiet] = []) {
    self.init(cta: cta, go: false, off: off, press: press, quiet: quiet, hasMore: false) { EmptyView() }
  }
}

// A box that writes: what it's about, a field and one named button. The page keeps the words (`draft`), so a sheet
// closed by mistake has them back; a write the desk refuses stays open with the desk's own words. As tall as what's
// in it, so it sits on the keyboard with its button in reach and the page still showing above.
struct WriteSheet<Above: View>: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  let title: String
  var prompt = ""
  let button: String
  var optional = false  // may be sent with nothing typed
  var go = false  // its button says yes: green
  var limit: Int?  // the most characters the desk takes: typing stops there, as the window's box
  var aside: (label: String, press: () -> Void)?  // a quiet way out beside the button: the box's Ask your agent
  @Binding var draft: String
  let send: (String) async -> Bool
  @ViewBuilder var above: () -> Above
  @State private var sending = false
  @State private var failed: String?
  @State private var tall: CGFloat = 200
  @FocusState private var typing: Bool

  var body: some View {
    let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SheetHead(title: title)
        above()
        TextField(prompt, text: $draft, axis: .vertical)
          .sans(15).foregroundStyle(Theme.ink).lineLimit(3...10).focused($typing)
          .onChange(of: draft) { _, typed in
            if let limit, typed.count > limit { draft = String(typed.prefix(limit)) }
          }
          .padding(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
          .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.ruleStrong, lineWidth: 1))
        if let failed { Text(failed).sans(13).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
        HStack(spacing: 8) {
          // It never reads what you typed: your words stay in this box's draft.
          if let aside {
            Button {
              dismiss()
              aside.press()
            } label: {
              Text(aside.label).sans(13, 550).underline(color: Theme.ruleStrong).foregroundStyle(Theme.ink2).frame(minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          Spacer(minLength: 0)
          Button(button) {
            Task {
              sending = true
              failed = await refusal(store) { await send(draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
              sending = false
              if failed == nil {
                draft = ""
                dismiss()
              }
            }
          }
          .buttonStyle(AccentAct(go: go))
          .disabled(sending || (empty && !optional))
        }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 14)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tall = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    // Taller than the room above the keyboard (large text): its foot shows, the field and the button that sends.
    .defaultScrollAnchor(.bottom)
    .presentationDetents([.height(tall)])
    .presentationBackground(Theme.paper)
    .task {
      // Once the sheet has settled: a field focused as it rises doesn't take it.
      try? await Task.sleep(for: .milliseconds(450))
      typing = true
    }
  }
}

extension WriteSheet where Above == EmptyView {
  init(
    title: String, prompt: String = "", button: String, optional: Bool = false, go: Bool = false, limit: Int? = nil, draft: Binding<String>,
    send: @escaping (String) async -> Bool
  ) {
    self.init(title: title, prompt: prompt, button: button, optional: optional, go: go, limit: limit, aside: nil, draft: draft, send: send) { EmptyView() }
  }
}

// Runs a write from a sheet, which covers the bubbles: nil once the desk took it, else why not, in the desk's words.
@MainActor
func refusal(_ store: Store, _ write: () async -> Bool) async -> String? {
  if await write() { return nil }
  return Words.sentence(store.whyNot ?? "It wasn't sent")
}

struct SheetHead: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  var close = "Cancel"

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      // Whole, on as many lines as it needs: its end says where the words go ("…stream.ts:12").
      Text(title).sans(16, 650, tracking: -0.01).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(close) { dismiss() }.sans(15, 500).tint(Theme.ink2)
    }
  }
}

// Who to ask to review your PR: GitHub's own picks first, a search for anyone else. A draft is marked ready with them.
// `keep`: one more reviewer on a PR that's already asked, which stays where it is.
struct ReviewersSheet: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  let card: Card
  var keep = false
  let done: () -> Void
  @State private var search = ""
  @State private var found: [Reviewer]?
  @State private var picked: [Reviewer] = []
  @State private var failed: String?
  @State private var sending = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SheetHead(title: "Ask reviewers on \(card.shortRef)")
        if card.draft == true { Text("Ready for review marks it ready, then asks them.").sans(13).foregroundStyle(Theme.pencil) }
        TextField("Search people and teams", text: $search)
          .sans(15).foregroundStyle(Theme.ink).textInputAutocapitalization(.never).autocorrectionDisabled()
          .padding(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
          .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.ruleStrong, lineWidth: 1))
        VStack(alignment: .leading, spacing: 0) {
          // Whoever's picked stays listed while the search moves on.
          let rows = picked.filter { p in !(found ?? []).contains { $0.id == p.id } } + (found ?? [])
          ForEach(rows) { r in row(r) }
          if found == nil, failed == nil { LoadingLines().padding(.vertical, 8) }
          if found?.isEmpty == true, picked.isEmpty {
            Text(search.isEmpty ? "GitHub suggests nobody: search for someone." : "Nobody matches.").sans(13).foregroundStyle(Theme.pencil)
              .padding(.vertical, 8)
          }
        }
        if let failed { Text(failed).sans(13).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
        Button(card.draft == true ? "Ready for review" : "Ask reviewers") {
          Task {
            sending = true
            failed = await refusal(store) {
              card.draft == true ? await store.ready(card, asking: picked) : await store.askReviewers(card, picked, keep: keep)
            }
            sending = false
            if failed == nil {
              dismiss()
              if !keep { done() }
            }
          }
        }
        .buttonStyle(AccentAct())
        .disabled(sending || picked.isEmpty)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 14)
    }
    .presentationDetents([.medium, .large])
    .presentationBackground(Theme.paper)
    .task(id: search) {
      // Typing settles before GitHub is asked.
      if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
      if Task.isCancelled { return }
      switch await store.fetchReviewers(card.id, search: search) {
      case .success(let list):
        found = list
        failed = nil
      case .failure(let e): failed = Words.sentence(e.words)
      case nil: break
      }
    }
  }

  private func row(_ r: Reviewer) -> some View {
    let on = picked.contains(r)
    return Button {
      if on { picked.removeAll { $0.id == r.id } } else { picked.append(r) }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(r.login).sans(15, on ? 600 : 400).foregroundStyle(Theme.ink).lineLimit(1)
        Text([r.name ?? "", r.team == true ? "team" : "", r.suggested == true ? "suggested" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
          .sans(13).foregroundStyle(Theme.pencil).lineLimit(1)
        Spacer(minLength: 8)
        if on { Text("✓").sans(15, 600).foregroundStyle(Theme.accentInk) }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}
