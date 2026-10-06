import SwiftUI
import QuotaCore

/// Equal columns keep Widgets directly beneath the app logo, regardless of label length.
struct OnboardingSurfacesView: View {
    let language: AppLanguage
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(WelcomeSurface.allCases) { surface in
                VStack(spacing: 8) {
                    WelcomeSurfaceIcon(surface: surface)
                        .frame(width: 56, height: 42).accessibilityHidden(true)
                    Text(AppText.value(surface.rawValue, language))
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center).lineLimit(2)
                        .frame(height: 30, alignment: .top)
                }.frame(maxWidth: .infinity)
            }
        }.frame(maxWidth: 360)
    }
}

private enum WelcomeSurface: String, CaseIterable, Identifiable {
    case menu = "Menu Bar", widgets = "Widgets", saver = "Screen Saver"
    var id: String { rawValue }
}

/// Small vector scenes share the silver shell and warm gold details of the app icon.
private struct WelcomeSurfaceIcon: View {
    let surface: WelcomeSurface
    @Environment(\.colorScheme) private var scheme
    private var gold: Color { QuotaClockColors.accent }
    var body: some View {
        Canvas { context, _ in
            let ink = Color.primary.opacity(scheme == .dark ? 0.64 : 0.52)
            let silver = Color(red: 0.69, green: 0.73, blue: 0.78)
            func panel(_ rect: CGRect, radius: CGFloat = 4, dark: Bool = false) {
                let path = Path(roundedRect: rect, cornerRadius: radius)
                let colors: [Color] = dark
                    ? [Color(white: 0.23), Color(white: 0.12)]
                    : [Color.white.opacity(scheme == .dark ? 0.22 : 0.95), silver.opacity(0.3)]
                context.fill(path, with: .linearGradient(Gradient(colors: colors),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                context.stroke(path, with: .color(ink.opacity(0.7)), lineWidth: 1)
            }
            func bar(_ rect: CGRect, _ color: Color) {
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(color))
            }
            func line(_ start: CGPoint, _ end: CGPoint, _ color: Color, width: CGFloat = 1) {
                var path = Path(); path.move(to: start); path.addLine(to: end)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            switch surface {
            case .menu:
                panel(CGRect(x: 5, y: 5, width: 46, height: 31), radius: 6)
                line(CGPoint(x: 6, y: 14), CGPoint(x: 50, y: 14), ink.opacity(0.35))
                for x in [10.5, 14.5, 18.5] {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: 8.5, width: 2, height: 2)), with: .color(ink.opacity(0.6)))
                }
                bar(CGRect(x: 35, y: 8, width: 10, height: 3), gold)
                panel(CGRect(x: 25, y: 14, width: 22, height: 17), radius: 3)
                bar(CGRect(x: 29, y: 18, width: 8, height: 2), gold)
                bar(CGRect(x: 29, y: 23, width: 13, height: 1.5), ink.opacity(0.4))
                bar(CGRect(x: 10, y: 21, width: 9, height: 2), ink.opacity(0.2))
            case .widgets:
                panel(CGRect(x: 5, y: 5, width: 26, height: 31), radius: 6)
                panel(CGRect(x: 34, y: 5, width: 17, height: 14))
                panel(CGRect(x: 34, y: 22, width: 17, height: 14))
                var gauge = Path()
                gauge.addArc(center: CGPoint(x: 18, y: 18), radius: 7,
                    startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                context.stroke(gauge, with: .color(gold), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                line(CGPoint(x: 18, y: 18), CGPoint(x: 21, y: 14), ink, width: 1.5)
                bar(CGRect(x: 12, y: 29, width: 12, height: 2), ink.opacity(0.4))
                bar(CGRect(x: 38, y: 9, width: 6, height: 2), gold)
                bar(CGRect(x: 38, y: 14, width: 9, height: 1.5), ink.opacity(0.3))
                for (index, height) in [3.0, 6, 4].enumerated() {
                    bar(CGRect(x: 38 + Double(index) * 3.5, y: 32 - height, width: 2, height: height), gold.opacity(0.65 + Double(index) * 0.15))
                }
            case .saver:
                line(CGPoint(x: 28, y: 33), CGPoint(x: 28, y: 38), ink, width: 3)
                bar(CGRect(x: 20, y: 38, width: 16, height: 2), ink)
                panel(CGRect(x: 4, y: 3, width: 48, height: 31), radius: 5, dark: true)
                context.fill(Path(roundedRect: CGRect(x: 8, y: 7, width: 23, height: 23), cornerRadius: 3), with: .color(silver.opacity(0.18)))
                bar(CGRect(x: 11, y: 11, width: 9, height: 2), .white.opacity(0.8))
                bar(CGRect(x: 11, y: 17, width: 13, height: 4), gold)
                bar(CGRect(x: 11, y: 25, width: 16, height: 1.5), .white.opacity(0.4))
                bar(CGRect(x: 36, y: 9, width: 11, height: 2), .white.opacity(0.85))
                for y in [16.0, 24] {
                    context.fill(Path(roundedRect: CGRect(x: 35, y: y, width: 13, height: 6), cornerRadius: 2), with: .color(silver.opacity(0.18)))
                    bar(CGRect(x: 37, y: y + 2, width: 7, height: 2), gold.opacity(0.8))
                }
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.08), radius: 2, y: 1)
    }
}
