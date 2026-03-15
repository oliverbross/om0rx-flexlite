import Foundation

public struct SubscriptionManager: Sendable {
    private var active: Set<SubscriptionTopic>

    public init(active: Set<SubscriptionTopic> = []) {
        self.active = active
    }

    public mutating func markActive(_ topic: SubscriptionTopic) {
        active.insert(topic)
    }

    public func missingSubscriptions(for desired: Set<SubscriptionTopic>) -> [SubscriptionTopic] {
        desired.subtracting(active).sorted { $0.rawValue < $1.rawValue }
    }
}
