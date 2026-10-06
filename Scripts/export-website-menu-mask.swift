import Foundation
import SwiftUI

// Clip the original native capture without repainting any UI pixels.
// Coordinates are logical points from the 372 × 600 website capture fixture:
// MenuCardsView padding/spacing + MenuCardLayout's 360 × 170 cards.
func outline(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) -> String {
    let path = RoundedRectangle(cornerRadius: radius, style: .continuous)
        .path(in: CGRect(x: x, y: y, width: width, height: height)).cgPath
    var commands: [String] = []
    func point(_ value: CGPoint) -> String {
        String(format: "%.3f %.3f", locale: Locale(identifier: "en_US_POSIX"), value.x, value.y)
    }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: commands.append("M" + point(e.points[0]))
        case .addLineToPoint: commands.append("L" + point(e.points[0]))
        case .addQuadCurveToPoint: commands.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
        case .addCurveToPoint: commands.append("C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
        case .closeSubpath: commands.append("Z")
        @unknown default: fatalError("Unsupported native path element")
        }
    }
    return "<path d=\"\(commands.joined(separator: " "))\"/>"
}

let cards = [6.0, 188.0, 370.0].map {
    outline(x: 6, y: $0, width: 360, height: 170, radius: 22)
}
let controls = [(4.0, 38.0), (50.0, 180.0), (238.0, 38.0), (284.0, 38.0), (330.0, 38.0)].map {
    outline(x: $0.0, y: 562, width: $0.1, height: 34, radius: 12)
}
print("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 372 600\" fill=\"white\">\n" + (cards + controls).joined(separator: "\n") + "\n</svg>")
