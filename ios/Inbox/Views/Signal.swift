import SwiftUI

// A phone's signal, as RowIcons.tsx's: four rising bars, filled with no outline. As many are lit as `lit`, all in its
// colour (one red, two orange, three yellow, four green); the rest are grey.
struct Signal: View {
  let lit: Int
  var said = ""  // what it stands for, read out: a phone has no tooltip

  // Its own vivid colours, the same in both appearances: the theme's red, amber and green are tuned for text.
  static func colour(_ lit: Int) -> Color {
    switch lit {
    case 1: Color(light: 0xff3b30, dark: 0xff3b30)
    case 2: Color(light: 0xff8a00, dark: 0xff8a00)
    case 3: Color(light: 0xf5c400, dark: 0xf5c400)
    default: Color(light: 0x1fc45a, dark: 0x1fc45a)
    }
  }

  var body: some View {
    Canvas { ctx, size in
      let k = size.width / 16
      for n in 0..<4 {
        let bar = CGRect(x: (1.4 + CGFloat(n) * 3.6) * k, y: (10 - CGFloat(n) * 2.8) * k, width: 2.4 * k, height: (4.4 + CGFloat(n) * 2.8) * k)
        ctx.fill(Path(roundedRect: bar, cornerRadius: 0.6 * k), with: .color(n < lit ? Signal.colour(lit) : Theme.pencil.opacity(0.55)))
      }
    }
    .frame(width: 16, height: 16)
    .accessibilityElement()
    .accessibilityLabel(said)
  }

  // One of a PR's facts, in words.
  struct Fact: Equatable {
    let said: String
  }

  static let risky: Set<String> = ["draft", "changes requested", "blocked", "handed back", "closed"]
  static let ci = ["green": "CI passing", "red": "CI failing", "pending": "CI running"]
  static let verdicts = ["look": "look closely", "skim": "skim it", "skip": "skip it"]

  // RowIcons.tsx's factsOf(): status (on the Inbox), CI, risk, size, read out beside the signal.
  static func facts(_ card: Card, stage: Bool) -> [Fact] {
    guard card.isPR else { return [] }
    var out: [Fact] = []
    if stage, let st = card.stage, !st.isEmpty { out.append(Fact(said: Words.capitalized(st))) }
    if let ci = card.ci, let said = Signal.ci[ci] {
      out.append(Fact(said: said))
    } else {
      out.append(Fact(said: "No checks"))
    }
    let verdict = card.preflight?.verdict ?? card.verdict
    if let risk = card.preflight?.risk ?? card.risk {
      let how = verdict.flatMap { verdicts[$0] }.map { ", \($0)" } ?? ""
      out.append(Fact(said: "\(Words.capitalized(risk)) risk\(how)"))
    } else {
      out.append(Fact(said: "No AI review yet"))
    }
    if let add = card.size?.add, let del = card.size?.del {
      let size = Words.sizeOf(add: add, del: del)
      out.append(Fact(said: String(size.label.split(separator: ":")[0])))
    }
    return out
  }

  // The AI review's risk, the bars a review shows; grey with no review yet.
  static func lit(_ card: Card) -> Int { (card.preflight?.risk ?? card.risk).map(Status.riskBars) ?? 0 }

  static func said(_ facts: [Fact]) -> String { facts.map(\.said).joined(separator: ". ") }
}
