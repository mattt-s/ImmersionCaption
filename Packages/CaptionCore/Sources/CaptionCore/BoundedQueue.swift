/// A FIFO queue that drops the oldest pending item when overloaded to limit caption lag.
/// The in-flight translation is managed separately by the session coordinator.
public struct BoundedQueue<Element> {
    private var items: [Element] = []
    public let capacity: Int
    public private(set) var droppedCount = 0
    public var count: Int { items.count }

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public mutating func append(_ element: Element) {
        if items.count == capacity {
            items.removeFirst()
            droppedCount += 1
        }
        items.append(element)
    }

    public mutating func popFirst() -> Element? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func removeAll() {
        items.removeAll()
        droppedCount = 0
    }
}
