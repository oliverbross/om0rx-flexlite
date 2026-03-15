import Foundation

public actor AdaptiveJitterBuffer<Element: Sendable> {
    private let capacity: Int
    private var items: [Element] = []
    private(set) var underrunCount = 0

    public init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    public func push(_ element: Element) {
        items.append(element)
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
    }

    public func pop() -> Element? {
        guard !items.isEmpty else {
            underrunCount += 1
            return nil
        }
        return items.removeFirst()
    }

    public func depth() -> Int {
        items.count
    }

    public func reset() {
        items.removeAll(keepingCapacity: false)
        underrunCount = 0
    }
}
