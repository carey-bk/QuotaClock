import SwiftUI

/// Keep the saver canvas black. Texture belongs only inside its glass cards.
struct AmbientBackdrop: View {
    var body: some View {
        Color.black.accessibilityHidden(true)
    }
}
