import SwiftUI

// Your agent's own mark, as the chat's head draws it (Chat.tsx's MARK: Lobe Icons' paths, lobehub/lobe-icons, MIT), in
// its 24×24 box. Fill it even-odd, as the window does.
struct AgentMark: Shape {
  let agent: String?

  static let paths = [
    "claude-code":
      "M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z",
    "codex":
      "M8.086.457a6.105 6.105 0 013.046-.415c1.333.153 2.521.72 3.564 1.7a.117.117 0 00.107.029c1.408-.346 2.762-.224 4.061.366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 01-.18 1.631.167.167 0 00.04.155 5.982 5.982 0 011.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 01-2.934 1.851.162.162 0 00-.108.102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21-1.736a.145.145 0 00-.14-.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 01-2.595-.622 6.058 6.058 0 01-2.146-1.781c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 01-.495-1.283 6.11 6.11 0 01-.017-3.064.166.166 0 00.008-.074.115.115 0 00-.037-.064 5.958 5.958 0 01-1.38-2.202 5.196 5.196 0 01-.333-1.589 6.915 6.915 0 01.188-2.132c.45-1.484 1.309-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129.129 0 00.087-.087A6.016 6.016 0 015.635 2.31C6.315 1.464 7.132.846 8.086.457zm-.804 7.85a.848.848 0 00-1.473.842l1.694 2.965-1.688 2.848a.849.849 0 001.46.864l1.94-3.272a.849.849 0 00.007-.854l-1.94-3.393zm5.446 6.24a.849.849 0 000 1.695h4.848a.849.849 0 000-1.696h-4.848z",
    "opencode": "M16 6H8v12h8V6zm4 16H4V2h16v20z",
  ]

  func path(in rect: CGRect) -> Path {
    SVGPath.parse(AgentMark.paths[agent ?? ""] ?? AgentMark.paths["claude-code"]!)
      .applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).translatedBy(x: rect.minX, y: rect.minY))
  }
}

// SVG path data as the marks use it (M L H V C S A Z, absolute and relative), so their paths stay the window's verbatim.
enum SVGPath {
  static func parse(_ d: String) -> Path {
    var p = Path()
    var nums: [Double] = []
    var at = CGPoint.zero, start = CGPoint.zero, ctrl: CGPoint?
    let tokens = tokenize(d)
    var i = 0
    func take(_ n: Int) -> [Double]? {
      guard i + n <= nums.count else { return nil }
      defer { i += n }
      return Array(nums[i..<i + n])
    }
    for (c, args) in tokens {
      nums = args
      i = 0
      let rel = c.isLowercase
      repeat {
        switch Character(c.uppercased()) {
        case "M":
          guard let v = take(2) else { break }
          at = CGPoint(x: (rel ? at.x : 0) + v[0], y: (rel ? at.y : 0) + v[1])
          if i == 2 { p.move(to: at); start = at } else { p.addLine(to: at) }
          ctrl = nil
        case "L":
          guard let v = take(2) else { break }
          at = CGPoint(x: (rel ? at.x : 0) + v[0], y: (rel ? at.y : 0) + v[1])
          p.addLine(to: at)
          ctrl = nil
        case "H":
          guard let v = take(1) else { break }
          at.x = (rel ? at.x : 0) + v[0]
          p.addLine(to: at)
          ctrl = nil
        case "V":
          guard let v = take(1) else { break }
          at.y = (rel ? at.y : 0) + v[0]
          p.addLine(to: at)
          ctrl = nil
        case "C":
          guard let v = take(6) else { break }
          let b = rel ? at : .zero
          let c1 = CGPoint(x: b.x + v[0], y: b.y + v[1]), c2 = CGPoint(x: b.x + v[2], y: b.y + v[3])
          at = CGPoint(x: b.x + v[4], y: b.y + v[5])
          p.addCurve(to: at, control1: c1, control2: c2)
          ctrl = c2
        case "S":
          guard let v = take(4) else { break }
          let b = rel ? at : .zero
          let c1 = ctrl.map { CGPoint(x: 2 * at.x - $0.x, y: 2 * at.y - $0.y) } ?? at
          let c2 = CGPoint(x: b.x + v[0], y: b.y + v[1])
          at = CGPoint(x: b.x + v[2], y: b.y + v[3])
          p.addCurve(to: at, control1: c1, control2: c2)
          ctrl = c2
        case "A":
          guard let v = take(7) else { break }
          let to = CGPoint(x: (rel ? at.x : 0) + v[5], y: (rel ? at.y : 0) + v[6])
          arc(&p, from: at, to: to, rx: v[0], ry: v[1], angle: v[2], large: v[3] != 0, sweep: v[4] != 0)
          at = to
          ctrl = nil
        case "Z":
          p.closeSubpath()
          at = start
          ctrl = nil
        default: i = nums.count
        }
      } while i < nums.count
    }
    return p
  }

  // Letters with their numbers; an arc's flags may run together ("013.046" is 0, 1, 3.046).
  private static func tokenize(_ d: String) -> [(Character, [Double])] {
    var out: [(Character, [Double])] = []
    var num = ""
    var argIndex = 0
    func flush() {
      if !num.isEmpty, let v = Double(num), !out.isEmpty { out[out.count - 1].1.append(v) }
      if !num.isEmpty { argIndex += 1 }
      num = ""
    }
    for ch in d {
      if ch.isLetter, ch != "e" {
        flush()
        out.append((ch, []))
        argIndex = 0
        continue
      }
      let inFlag = (out.last?.0 == "a" || out.last?.0 == "A") && [3, 4].contains(argIndex % 7)
      if inFlag, ch == "0" || ch == "1" {
        flush()
        num = String(ch)
        flush()
        continue
      }
      if ch == "-", !num.isEmpty, num.last != "e" {
        flush()
        num = "-"
      } else if ch == ".", num.contains(".") {
        flush()
        num = "."
      } else if ch == " " || ch == "," {
        flush()
      } else {
        num.append(ch)
      }
    }
    flush()
    return out
  }

  // The SVG spec's endpoint arc as a circle's arc stretched to the ellipse (F.6.5).
  private static func arc(_ p: inout Path, from a: CGPoint, to b: CGPoint, rx: Double, ry: Double, angle: Double, large: Bool, sweep: Bool) {
    var rx = abs(rx), ry = abs(ry)
    if rx == 0 || ry == 0 || a == b {
      p.addLine(to: b)
      return
    }
    let phi = angle * .pi / 180
    let (cs, sn) = (cos(phi), sin(phi))
    let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
    let x1 = cs * dx + sn * dy, y1 = -sn * dx + cs * dy
    let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lambda > 1 {
      rx *= lambda.squareRoot()
      ry *= lambda.squareRoot()
    }
    let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let k = (large == sweep ? -1.0 : 1.0) * max(0, num / den).squareRoot()
    let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
    let cx = cs * cx1 - sn * cy1 + (a.x + b.x) / 2, cy = sn * cx1 + cs * cy1 + (a.y + b.y) / 2
    func ang(_ ux: Double, _ uy: Double) -> Double { atan2(uy, ux) }
    let t1 = ang((x1 - cx1) / rx, (y1 - cy1) / ry)
    var dt = ang((-x1 - cx1) / rx, (-y1 - cy1) / ry) - t1
    if sweep, dt < 0 { dt += 2 * .pi }
    if !sweep, dt > 0 { dt -= 2 * .pi }
    let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: phi).scaledBy(x: rx, y: ry)
    p.addRelativeArc(center: .zero, radius: 1, startAngle: .radians(t1), delta: .radians(dt), transform: t)
  }
}
