import SwiftUI
import QuotaCore

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .dark: .dark; case .light: .light }
    }
}
