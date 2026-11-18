import SwiftUI

// A row's icons, RowIcons.tsx's 16×16 paths, stroked 1.5 with round ends in the colour they're given.
enum Glyph: String {
  case pr, issue, question, session, note, agent, clock

  // What it stands for, read out where the icon is all a row shows.
  var said: String {
    switch self {
    case .pr: "PR"
    case .issue: "Issue"
    case .question: "Question"
    case .session: "Session"
    case .note: "Note"
    case .agent: "Agent"
    case .clock: "Reminder"
    }
  }

  // The parts that are filled, not stroked: an issue's dot, a question's.
  var dots: [(CGPoint, CGFloat)] {
    switch self {
    case .issue: [(.init(x: 8, y: 8), 1.25)]
    case .question: [(.init(x: 8, y: 11.3), 0.6)]
    default: []
    }
  }

  var path: Path {
    var p = Path()
    let ring = { p.addEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12)) }
    let circle = { (x: CGFloat, y: CGFloat, r: CGFloat) in p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    let line = { (points: [(CGFloat, CGFloat)]) in
      p.move(to: CGPoint(x: points[0].0, y: points[0].1))
      for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    }
    switch self {
    case .pr:
      circle(4, 3.75, 1.75)
      circle(4, 12.25, 1.75)
      circle(12, 12.25, 1.75)
      line([(4, 5.5), (4, 10.5)])
      // M12 10.5v-4a2 2 0 0 0-2-2H8
      line([(12, 10.5), (12, 6.5)])
      p.addArc(center: CGPoint(x: 10, y: 6.5), radius: 2, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
      p.addLine(to: CGPoint(x: 8, y: 4.5))
      line([(9.5, 2.75), (7.75, 4.5), (9.5, 6.25)])
    case .issue:
      ring()
    case .question:
      ring()
      // M6.3 6.4a1.8 1.8 0 1 1 2.7 1.55c-.6.35-1 .75-1 1.35
      p.move(to: CGPoint(x: 6.3, y: 6.4))
      p.addArc(center: CGPoint(x: 8.1, y: 6.39), radius: 1.8, startAngle: .degrees(180), endAngle: .degrees(420), clockwise: false)
      p.addCurve(to: CGPoint(x: 8, y: 9.3), control1: CGPoint(x: 8.4, y: 8.3), control2: CGPoint(x: 8, y: 8.7))
    case .session:
      p.addRoundedRect(in: CGRect(x: 1.75, y: 2.75, width: 12.5, height: 10.5), cornerSize: CGSize(width: 2, height: 2))
      line([(4.75, 6.25), (6.75, 8), (4.75, 9.75)])
      line([(8.5, 10), (11, 10)])
    case .note:
      line([(3.5, 2.5), (9.5, 2.5), (12.5, 5.5), (12.5, 13.5), (3.5, 13.5)])
      p.closeSubpath()
      line([(9.5, 2.5), (9.5, 5.5), (12.5, 5.5)])
      line([(5.75, 8.75), (10.25, 8.75)])
      line([(5.75, 11), (8.75, 11)])
    case .agent:
      p.addRoundedRect(in: CGRect(x: 2.75, y: 5.25, width: 10.5, height: 8), cornerSize: CGSize(width: 2.25, height: 2.25))
      line([(8, 5.25), (8, 3.25)])
      line([(6.1, 8.75), (6.1, 9.75)])
      line([(9.9, 8.75), (9.9, 9.75)])
      circle(8, 2.5, 0.75)
    case .clock:
      ring()
      line([(8, 4.75), (8, 8), (10.1, 9.3)])
    }
    return p
  }
}

struct GlyphView: View {
  let glyph: Glyph
  var color: Color = Theme.pencil
  var side: CGFloat = 16

  var body: some View {
    Canvas { ctx, size in
      ctx.scaleBy(x: size.width / 16, y: size.height / 16)
      ctx.stroke(glyph.path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
      for (c, r) in glyph.dots {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
      }
    }
    .frame(width: side, height: side)
    .accessibilityElement()
    .accessibilityLabel(glyph.said)
  }
}

// Who a row is from, as their picture alone in a slot of its own: yours, a person's, a robot for a bot or an agent, a
// clock for a note's reminder. The slot keeps its room when a picture doesn't load.
struct RowFace: View {
  enum Who {
    case person(String)  // a login: yours too
    case glyph(Glyph)
  }

  let who: Who
  let said: String

  var body: some View {
    Group {
      switch who {
      case .person(let login): Avatar(login: login, size: 18, trailing: 0, scales: false)
      case .glyph(let g): GlyphView(glyph: g)
      }
    }
    .frame(width: 18, height: 18)
    .accessibilityElement()
    .accessibilityLabel(said)
  }
}
