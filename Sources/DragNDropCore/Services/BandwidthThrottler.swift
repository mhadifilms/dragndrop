import Foundation

// MARK: - Bandwidth Throttler

/// Manages bandwidth throttling for uploads using a token bucket algorithm
public actor BandwidthThrottler {
    private var maxBytesPerSecond: Int64
    private var availableTokens: Int64
    private var lastRefillTime: Date
    private let refillInterval: TimeInterval = 0.1  // Refill every 100ms for smooth throttling

    // Stats
    private var totalBytesThrottled: Int64 = 0
    private var totalDelayTime: TimeInterval = 0

    public init(maxBytesPerSecond: Int64 = 0) {
        self.maxBytesPerSecond = maxBytesPerSecond
        self.availableTokens = maxBytesPerSecond
        self.lastRefillTime = Date()
    }

    // MARK: - Configuration

    /// Updates the maximum bytes per second limit
    public func setLimit(bytesPerSecond: Int64) {
        maxBytesPerSecond = bytesPerSecond
        availableTokens = min(availableTokens, bytesPerSecond)
    }

    /// Sets the limit from megabytes per second
    public func setLimit(mbps: Double) {
        setLimit(bytesPerSecond: Int64(mbps * 1024 * 1024))
    }

    /// Disables throttling (unlimited bandwidth)
    public func disable() {
        maxBytesPerSecond = 0
    }

    /// Returns whether throttling is enabled
    public var isEnabled: Bool {
        maxBytesPerSecond > 0
    }

    /// Returns the current limit in bytes per second
    public var currentLimitBps: Int64 {
        maxBytesPerSecond
    }

    /// Returns the current limit formatted as a string
    public var currentLimitFormatted: String {
        guard maxBytesPerSecond > 0 else { return "Unlimited" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: maxBytesPerSecond))/s"
    }

    // MARK: - Throttling

    /// Requests permission to send a certain number of bytes
    /// Returns the number of bytes that can be sent immediately
    /// May delay execution to enforce bandwidth limits
    public func requestBytes(_ requestedBytes: Int64) async -> Int64 {
        guard maxBytesPerSecond > 0 else {
            return requestedBytes  // No throttling
        }

        // Refill tokens based on elapsed time
        refillTokens()

        // Calculate how many bytes we can send now
        let bytesToSend = min(requestedBytes, availableTokens)

        if bytesToSend > 0 {
            availableTokens -= bytesToSend
            return bytesToSend
        }

        // Need to wait for tokens - calculate wait time
        let bytesNeeded = min(requestedBytes, maxBytesPerSecond)  // Cap at 1 second worth
        let tokensNeeded = bytesNeeded - availableTokens
        let waitTime = TimeInterval(tokensNeeded) / TimeInterval(maxBytesPerSecond)

        // Wait and track delay
        totalDelayTime += waitTime
        totalBytesThrottled += bytesNeeded

        try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))

        // After waiting, refill and return the requested amount
        refillTokens()
        availableTokens -= bytesNeeded
        return bytesNeeded
    }

    /// Convenience method that waits until all requested bytes are available
    public func waitForBytes(_ bytes: Int64) async {
        guard maxBytesPerSecond > 0 else { return }

        var remaining = bytes
        while remaining > 0 {
            let granted = await requestBytes(remaining)
            remaining -= granted
        }
    }

    /// Returns how long to wait before sending the specified number of bytes
    public func estimatedWaitTime(forBytes bytes: Int64) -> TimeInterval {
        guard maxBytesPerSecond > 0 else { return 0 }

        refillTokens()
        if bytes <= availableTokens {
            return 0
        }

        let tokensNeeded = bytes - availableTokens
        return TimeInterval(tokensNeeded) / TimeInterval(maxBytesPerSecond)
    }

    // MARK: - Token Bucket Algorithm

    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)

        if elapsed >= refillInterval {
            let tokensToAdd = Int64(elapsed * Double(maxBytesPerSecond))
            availableTokens = min(availableTokens + tokensToAdd, maxBytesPerSecond)
            lastRefillTime = now
        }
    }

    // MARK: - Statistics

    /// Returns the total bytes that were throttled
    public var throttledBytes: Int64 {
        totalBytesThrottled
    }

    /// Returns the total time spent waiting due to throttling
    public var delayTime: TimeInterval {
        totalDelayTime
    }

    /// Resets statistics
    public func resetStats() {
        totalBytesThrottled = 0
        totalDelayTime = 0
    }
}

// MARK: - Throttled Data Stream

/// A helper that wraps data chunks and applies throttling
public actor ThrottledDataStream {
    private let throttler: BandwidthThrottler
    private let chunkSize: Int64

    public init(throttler: BandwidthThrottler, chunkSize: Int64 = 64 * 1024) {
        self.throttler = throttler
        self.chunkSize = chunkSize
    }

    /// Yields data in throttled chunks
    public func throttledChunks(of data: Data) -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                var offset = 0
                while offset < data.count {
                    let remainingBytes = data.count - offset
                    let currentChunkSize = min(Int(chunkSize), remainingBytes)

                    // Wait for permission to send this chunk
                    _ = await throttler.requestBytes(Int64(currentChunkSize))

                    let chunk = data[offset..<(offset + currentChunkSize)]
                    continuation.yield(Data(chunk))
                    offset += currentChunkSize
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Bandwidth Monitor

/// Monitors actual bandwidth usage
public actor BandwidthMonitor {
    private var samples: [(timestamp: Date, bytes: Int64)] = []
    private let sampleWindowSeconds: TimeInterval = 10  // Keep 10 seconds of samples
    private let maxSamples = 100

    public init() {}

    /// Records bytes transferred
    public func recordBytes(_ bytes: Int64) {
        let now = Date()
        samples.append((timestamp: now, bytes: bytes))

        // Clean old samples
        let cutoff = now.addingTimeInterval(-sampleWindowSeconds)
        samples = samples.filter { $0.timestamp > cutoff }

        // Keep sample count manageable
        if samples.count > maxSamples {
            samples = Array(samples.suffix(maxSamples))
        }
    }

    /// Returns the current average speed in bytes per second
    public var currentSpeed: Double {
        guard samples.count >= 2 else { return 0 }

        let totalBytes = samples.reduce(0) { $0 + $1.bytes }
        guard let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else { return 0 }

        let duration = last.timeIntervalSince(first)
        guard duration > 0 else { return 0 }

        return Double(totalBytes) / duration
    }

    /// Returns the current speed formatted as a string
    public var currentSpeedFormatted: String {
        let speed = currentSpeed
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }

    /// Resets the monitor
    public func reset() {
        samples = []
    }
}
