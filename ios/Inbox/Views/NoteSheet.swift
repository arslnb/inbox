import SwiftUI

// New note, or one you opened: your words, where it goes on your Inbox and an optional reminder, as the window's note box. Save sends it; Done
// (an existing note's) takes it off your desk for good; a refusal keeps your words here with the desk's own.
struct NoteSheet: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  let note: Note?
  @State private var text: String
  @State private var section: String
  @State private var pick: String
  @State private var at: Date
  @State private var opened = Date()  // the earliest time to pick
  @State private var sending = false
  @State private var failed: String?
  @State private var tall: CGFloat = 260
  @FocusState private var typing: Bool

  init(note: Note?, draft: String) {
    self.note = note
    _text = State(initialValue: note?.text ?? draft)
    _section = State(initialValue: note?.section ?? "standard")
    let reminds = Words.date(note?.remindAt)
    _pick = State(initialValue: reminds == nil ? "" : "pick")
    _at = State(initialValue: reminds ?? Remind.nextHour(Date()))
  }

  var body: some View {
    let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SheetHead(title: note == nil ? "New note to yourself" : "Your note", close: "Close")
        TextField("Remind me to…", text: $text, axis: .vertical)
          .sans(15).foregroundStyle(Theme.ink).lineLimit(3...10).focused($typing)
          .onChange(of: text) { _, typed in
            if typed.count > Words.maxAsk { text = String(typed.prefix(Words.maxAsk)) }
            // A new note's words are kept for a sheet closed by mistake.
            if note == nil { store.noteDraft = text }
          }
          .padding(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
          .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.ruleStrong, lineWidth: 1))
        // A due reminder leads Urgent whatever is picked here.
        choice("In", $section, Lists.sections.map { ($0, Lists.sectionName[$0] ?? $0) })
        choice("Remind me", $pick, Remind.choices)
        if pick == "pick" {
          // Not before now; a reminder that already came keeps its own time until you move it.
          DatePicker("Remind me at", selection: $at, in: min(opened, at)...)
            .labelsHidden().datePickerStyle(.compact).tint(Theme.accentInk)
        }
        if let failed { Text(failed).sans(13).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
        HStack(spacing: 6) {
          Spacer(minLength: 0)
          if let note {
            Button("Done") {
              dismiss()
              Task { await store.doneNote(note) }
            }
            .buttonStyle(PlainAct())
          }
          Button(sending ? "Saving…" : "Save") {
            Task {
              sending = true
              failed = await refusal(store) {
                await store.saveNote(
                  note, text: text.trimmingCharacters(in: .whitespacesAndNewlines), remind: Remind.value(pick, at: at, was: note), section: section)
              }
              sending = false
              if failed == nil { dismiss() }
            }
          }
          .buttonStyle(AccentAct())
          .disabled(sending || empty)
        }
      }
      .padding(.horizontal, Theme.pad)
      .padding(.vertical, 14)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tall = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents([.height(tall)])
    .presentationBackground(Theme.paper)
    .task {
      // Once the sheet has settled: a field focused as it rises doesn't take it.
      try? await Task.sleep(for: .milliseconds(450))
      typing = true
    }
  }

  // A label and its menu of choices, the picked one's words shown.
  private func choice(_ label: String, _ value: Binding<String>, _ choices: [(value: String, label: String)]) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label).sans(14).foregroundStyle(Theme.pencil)
      Menu {
        Picker(label, selection: value) {
          ForEach(choices, id: \.value) { c in Text(c.label).tag(c.value) }
        }
      } label: {
        HStack(spacing: 5) {
          Text(choices.first { $0.value == value.wrappedValue }?.label ?? "").sans(14, 500).foregroundStyle(Theme.ink)
          Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.pencil)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle().inset(by: -4))
      }
      Spacer(minLength: 0)
    }
  }
}
