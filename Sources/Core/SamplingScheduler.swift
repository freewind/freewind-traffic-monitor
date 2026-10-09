import Foundation

/// 周期性采样：调用 nettop 取快照、换算成本轮新增、写入 SQLite。
///
/// - 采样在专用串行队列上执行，保证不会出现两次采样重叠
/// - 每次采样后立即落库，因此进程被强杀时最多丢失一个采样间隔的数据
///
/// `@unchecked Sendable` 的依据：可变状态（timer、aggregator）只在私有串行队列上访问，
/// `store` 只在该队列内使用；`onSample` / `onError` 在 `start()` 前设置。
public final class SamplingScheduler: @unchecked Sendable {
    public struct Sample: Sendable {
        public let timestamp: Int64
        public let deltas: [TrafficDelta]
    }

    public var onSample: (@Sendable (Sample) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    private let store: SQLiteStore
    private let interval: TimeInterval
    private let collector: () throws -> [ProcessTraffic]
    private let now: () -> Int64
    private let aggregator = TrafficAggregator()
    private let queue = DispatchQueue(label: "freewind-traffic-monitor.sampling")
    private var timer: DispatchSourceTimer?

    public init(
        store: SQLiteStore,
        interval: TimeInterval = 5,
        collector: @escaping () throws -> [ProcessTraffic] = NettopCollector.snapshot,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) {
        self.store = store
        self.interval = interval
        self.collector = collector
        self.now = now
    }

    public func start() {
        queue.async {
            guard self.timer == nil else {
                return
            }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                self?.sampleOnce()
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    /// 立即采样一次，用于退出前把最后一段流量落库。
    public func flush() {
        queue.sync {
            sampleOnce()
        }
    }

    private func sampleOnce() {
        do {
            let snapshot = try collector()
            let timestamp = now()
            let deltas = aggregator.ingest(snapshot, at: timestamp)
            try store.record(deltas)
            onSample?(Sample(timestamp: timestamp, deltas: deltas))
        } catch {
            onError?(error)
        }
    }
}
