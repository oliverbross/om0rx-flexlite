import Diagnostics
import Foundation

public struct CWMacro: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

public actor CWEngine {
    private let diagnostics: DiagnosticsCenter?
    private var queue: [(block: Int, text: String)] = []
    private var macros: [CWMacro]
    private(set) var wordsPerMinute: Int
    private var nextBlock = 1

    public init(diagnostics: DiagnosticsCenter? = nil, macros: [CWMacro] = [], wordsPerMinute: Int = 22) {
        self.diagnostics = diagnostics
        self.macros = macros
        self.wordsPerMinute = wordsPerMinute
    }

    public func setWordsPerMinute(_ value: Int) {
        wordsPerMinute = max(5, min(value, 60))
    }

    public func saveMacro(_ macro: CWMacro) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            macros.append(macro)
        }
    }

    public func allMacros() -> [CWMacro] {
        macros.sorted { $0.title < $1.title }
    }

    public func nextBlockIdentifier() -> Int {
        defer { nextBlock += 1 }
        return nextBlock
    }

    public func send(text: String, block: Int) async {
        queue.append((block, text))
        if let diagnostics {
            await diagnostics.log(.info, "Queued CW text", metadata: ["count": "\(text.count)", "block": "\(block)"])
        }
    }

    public func insert(text: String, block: Int) {
        queue.insert((block, text), at: 0)
    }

    public func clear() {
        queue.removeAll()
    }

    public func dequeue() -> String? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst().text
    }

    public func pendingCount() -> Int {
        queue.count
    }
}
