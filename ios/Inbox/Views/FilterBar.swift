import SwiftUI
import UIKit

// A list's filter, under its page's name: words match a row's title, repo or author; author:dana and involves:dana pick
// people, each a pill once finished, suggested as rows under the box while you type (Filter.tsx). One filter for the
// Inbox, Blocked and the Archive, as the window's.
struct FilterBar: View {
  @Environment(Store.self) private var store
  @State private var focused = false
  @State private var open = false  // the suggestions; a person picked closes them until you type again
  @ScaledMetric(relativeTo: .body) private var keyWidth: CGFloat = 72  // "Involves", with room before who

  private var startFocused: Bool {
    #if DEBUG
      store.debugFilterFocus
    #else
      false
    #endif
  }

  var body: some View {
    @Bindable var store = store
    let pills = Filter.parse(store.filter).terms.filter(\.done)
    let rest = Filter.rest(store.filter)
    let people = store.queue.map { Filter.people(Filter.cards($0), me: store.me) } ?? []
    let offered = focused && open ? Filter.offered(store.filter, people) : []
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.pencil).accessibilityHidden(true)
        ForEach(Array(pills.enumerated()), id: \.offset) { i, t in pill(t) { store.filter = Filter.dropped(i, from: store.filter) } }
        FilterField(
          text: Binding(
            get: { rest },
            set: {
              store.filter = Filter.of(pills, $0)
              open = true
            }), focused: $focused, placeholder: pills.isEmpty ? "Filter" : "", startFocused: startFocused
        ) {
          // Backspace at the box's start takes the last pill off.
          store.filter = Filter.dropped(from: store.filter)
        }
        .frame(minWidth: 60)
        if !store.filter.isEmpty {
          Button("Clear") {
            store.filter = ""
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
          }
          .buttonStyle(.plain).sans(13).foregroundStyle(Theme.pencil)
          .frame(minHeight: 44).contentShape(Rectangle().inset(by: -6))
        }
      }
      .padding(.horizontal, Theme.pad)
      if !offered.isEmpty {
        Theme.rule.frame(height: 1)
        VStack(alignment: .leading, spacing: 0) {
          if Filter.word(rest).isEmpty {
            Text("Filter by person").sans(12.5, 550).foregroundStyle(Theme.pencil)
              .padding(.init(top: 10, leading: Theme.pad, bottom: 2, trailing: Theme.pad))
          }
          ForEach(offered) { p in suggestion(p) }
        }
        .padding(.bottom, 4)
      }
    }
    // One line with a box in it: past the largest standard size a pill would leave the box no room. The rows below it grow on.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .background(Theme.paper)
    .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    .onChange(of: focused) { _, now in if now { open = true } }
  }

  // A finished term, as plain words: "Author dana ×". A press takes it off.
  private func pill(_ t: Filter.Term, drop: @escaping () -> Void) -> some View {
    let you = Filter.isYou(t.who.lowercased())
    return Button(action: drop) {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text((Filter.label[t.key] ?? t.key) + " ").foregroundStyle(Theme.pencil).fixedSize()
        if !you { Avatar(login: t.who) }
        Text(you ? "you" : t.who).sans(14, 550).foregroundStyle(Theme.ink).lineLimit(1)
        Text(" ×").foregroundStyle(Theme.pencil).fixedSize()
      }
      .sans(14)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Remove \((Filter.label[t.key] ?? t.key).lowercased()) \(t.who)")
  }

  private func suggestion(_ p: Filter.Pick) -> some View {
    Button {
      store.filter = Filter.picked(p, in: store.filter)
      open = p.login.isEmpty
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(Filter.label[p.key] ?? p.key).sans(14).foregroundStyle(Theme.pencil).fixedSize().frame(width: keyWidth, alignment: .leading)
        if p.login.isEmpty {
          Text(Filter.help[p.key] ?? "").sans(14).foregroundStyle(Theme.ink2).lineLimit(1).minimumScaleFactor(0.85)
        } else {
          if p.login != store.me { Avatar(login: p.login, size: 16) }
          Text(p.login).sans(14, 500).foregroundStyle(Theme.ink).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Theme.pad)
      .frame(minHeight: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPress())
  }
}

// The box itself: UIKit's field, since SwiftUI's can't tell a Backspace at its start (which takes the last pill off).
private struct FilterField: UIViewRepresentable {
  @Binding var text: String
  @Binding var focused: Bool  // told, never set from outside: the field's own taps and Done decide
  var placeholder: String
  var startFocused = false
  var backspaceAtStart: () -> Void

  final class Field: UITextField {
    var backspaceAtStart: (() -> Void)?

    override func deleteBackward() {
      if let at = selectedTextRange, at.isEmpty, compare(at.start, to: beginningOfDocument) == .orderedSame { backspaceAtStart?() }
      super.deleteBackward()
    }
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: FilterField
    init(_ parent: FilterField) { self.parent = parent }

    @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
    func textFieldDidBeginEditing(_ field: UITextField) { parent.focused = true }
    func textFieldDidEndEditing(_ field: UITextField) { parent.focused = false }
    func textFieldShouldReturn(_ field: UITextField) -> Bool {
      field.resignFirstResponder()
      return false
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> Field {
    let field = Field()
    field.delegate = context.coordinator
    field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
    field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: Typeface.sans.font(15), maximumPointSize: 24)
    field.adjustsFontForContentSizeCategory = true
    field.textColor = UIColor(Theme.ink)
    field.tintColor = UIColor(Theme.accentInk)
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.spellCheckingType = .no
    field.smartDashesType = .no
    field.smartQuotesType = .no
    field.returnKeyType = .done
    field.accessibilityLabel = "Filter by title, repo or person"
    if startFocused { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { field.becomeFirstResponder() } }
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  // All the width it's offered, one line tall: the whole of it takes a tap.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: Field, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 200, height: 44)
  }

  func updateUIView(_ field: Field, context: Context) {
    context.coordinator.parent = self
    field.backspaceAtStart = backspaceAtStart
    if field.text != text { field.text = text }
    field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(Theme.faint)])
  }
}
