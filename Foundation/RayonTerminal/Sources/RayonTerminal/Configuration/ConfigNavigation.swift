import SwiftUI

/// Which category Settings shows, and the ones it showed before. The app can
/// hold one to open Settings at a category.
@MainActor
public final class ConfigNavigation: ObservableObject {
    @Published public private(set) var selection: String
    @Published private var history: [String]
    @Published private var index = 0

    public init(_ selection: String = "general") {
        self.selection = selection
        history = [selection]
    }

    public func go(_ id: String) {
        guard id != selection else { return }
        history = Array(history.prefix(index + 1)) + [id]
        index = history.count - 1
        selection = id
    }

    public var canGoBack: Bool {
        index > 0
    }

    public var canGoForward: Bool {
        index + 1 < history.count
    }

    public func step(_ delta: Int) {
        let next = index + delta
        guard history.indices.contains(next) else { return }
        index = next
        selection = history[next]
    }
}
