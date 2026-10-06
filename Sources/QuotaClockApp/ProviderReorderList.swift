import SwiftUI
import AppKit
import QuotaCore

/// Move the actual row under the pointer. The layout keeps its place while the
/// surrounding rows spring into their new positions; expanded details travel too.
struct ProviderReorderList<Content: View>: View {
    let ids: [String]
    let enabled: Bool
    let language: AppLanguage
    let commit: ([String]) -> Void
    @ViewBuilder var content: (String, ProviderDragHandle) -> Content
    @State private var order: [String] = []
    @State private var frames: [String: CGRect] = [:]
    @State private var originalOrder: [String] = []
    @State private var originalFrames: [String: CGRect] = [:]
    @State private var handles: [String: CGFloat] = [:]
    @State private var originalHandles: [String: CGFloat] = [:]
    @State private var dragged: String?
    @State private var translation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spacing: CGFloat = 4
    private var animation: Animation? { reduceMotion ? nil : .interactiveSpring(response: 0.26, dampingFraction: 0.86) }
    private var rows: [String] { order.isEmpty ? ids : order }
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { id in
                content(id, ProviderDragHandle(id: id, enabled: enabled && ids.count > 1, language: language,
                    changed: { change(id, value: $0) }, ended: { finish() }, cancelled: { cancel() },
                    move: { move(id, by: $0) }))
                    .frame(height: dragged == nil ? nil : originalFrames[id]?.height)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ProviderRowFrames.self, value: [id: geometry.frame(in: .named("providerOrder"))])
                    })
                    .background(dragged == id ? Color(nsColor: .windowBackgroundColor) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(dragged == id ? 0.16 : 0), radius: dragged == id ? 12 : 0, y: dragged == id ? 5 : 0)
                    .offset(y: dragged == id ? dragOffset(id) : 0)
                    .zIndex(dragged == id ? 1 : 0)
                    .transaction { if dragged == id { $0.animation = nil } }
            }
        }
        .coordinateSpace(name: "providerOrder")
        .onPreferenceChange(ProviderRowFrames.self) { if dragged == nil { frames = $0 } }
        .onPreferenceChange(ProviderHandleCenters.self) { if dragged == nil { handles = $0 } }
        .onAppear { order = ids }
        .onChange(of: ids) { _, next in cancel(); order = next }
        .onChange(of: enabled) { _, value in if !value { cancel() } }
        .onDisappear { cancel() }
        .onExitCommand { cancel() }
    }
    private func dragOffset(_ id: String) -> CGFloat {
        guard let start = originalFrames[id], let first = originalOrder.first,
              let index = order.firstIndex(of: id) else { return 0 }
        let layoutY = (originalFrames[first]?.minY ?? 0) + order.prefix(index).reduce(0) {
            $0 + (originalFrames[$1]?.height ?? 0) + spacing
        }
        return start.minY + translation - layoutY
    }
    private func change(_ id: String, value: DragGesture.Value) {
        guard enabled, frames[id] != nil, handles[id] != nil else { return }
        if dragged == nil {
            originalOrder = rows; originalFrames = frames; originalHandles = handles; order = rows
            dragged = id; NSCursor.closedHand.set()
        }
        guard dragged == id, let anchor = originalHandles[id] else { return }
        translation = value.translation.height
        var next = originalOrder.filter { $0 != id }
        let center = anchor + translation
        let index = next.prefix { (originalHandles[$0] ?? .infinity) < center }.count
        next.insert(id, at: index)
        if order != next { withAnimation(animation) { order = next } }
    }
    private func finish() {
        guard dragged != nil else { return }
        let next = order
        withAnimation(animation) { dragged = nil; translation = 0 }
        NSCursor.openHand.set()
        commit(next)
    }
    private func cancel() {
        guard dragged != nil else { return }
        withAnimation(animation) { order = originalOrder; dragged = nil; translation = 0 }
        NSCursor.arrow.set()
    }
    private func move(_ id: String, by delta: Int) {
        guard enabled, dragged == nil, let from = rows.firstIndex(of: id) else { return }
        let destination = from + delta
        guard rows.indices.contains(destination) else { return }
        var next = rows; next.swapAt(from, destination)
        withAnimation(animation) { order = next }
        commit(next)
    }
}

struct ProviderDragHandle: View {
    let id: String
    let enabled: Bool
    let language: AppLanguage
    var changed: (DragGesture.Value) -> Void
    var ended: () -> Void
    var cancelled: () -> Void
    var move: (Int) -> Void
    @GestureState private var isDragging = false
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .frame(width: 18, height: 32).contentShape(Rectangle())
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ProviderHandleCenters.self, value: [id: geometry.frame(in: .named("providerOrder")).midY])
            })
            .opacity(enabled ? 1 : 0.3)
            .help(t("Drag to Reorder"))
            .accessibilityLabel(t("Drag to Reorder"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(t("Move Up"))) { move(-1) }
            .accessibilityAction(named: Text(t("Move Down"))) { move(1) }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("providerOrder"))
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { if enabled { changed($0) } }
                .onEnded { _ in ended() })
            .onChange(of: isDragging) { _, active in
                // A gesture cancelled by Escape/window changes has no onEnded.
                if !active { DispatchQueue.main.async { cancelled() } }
            }
            .onHover { inside in
                if enabled && !isDragging { (inside ? NSCursor.openHand : NSCursor.arrow).set() }
            }
    }
}

private struct ProviderRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ProviderHandleCenters: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
