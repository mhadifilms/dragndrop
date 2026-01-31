import Foundation

// MARK: - AWS Region

/// Represents an AWS region with S3 availability
public struct AWSRegion: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String  // e.g., "us-east-1"
    public let name: String  // e.g., "US East (N. Virginia)"
    public let city: String  // e.g., "N. Virginia"
    public let continent: Continent
    public let flag: String  // Emoji flag

    public enum Continent: String, Codable, CaseIterable, Sendable {
        case northAmerica = "North America"
        case southAmerica = "South America"
        case europe = "Europe"
        case asia = "Asia Pacific"
        case middleEast = "Middle East"
        case africa = "Africa"
    }

    public init(id: String, name: String, city: String, continent: Continent, flag: String) {
        self.id = id
        self.name = name
        self.city = city
        self.continent = continent
        self.flag = flag
    }

    // MARK: - All S3 Regions

    public static let allRegions: [AWSRegion] = [
        // North America
        AWSRegion(id: "us-east-1", name: "US East (N. Virginia)", city: "N. Virginia", continent: .northAmerica, flag: "🇺🇸"),
        AWSRegion(id: "us-east-2", name: "US East (Ohio)", city: "Ohio", continent: .northAmerica, flag: "🇺🇸"),
        AWSRegion(id: "us-west-1", name: "US West (N. California)", city: "N. California", continent: .northAmerica, flag: "🇺🇸"),
        AWSRegion(id: "us-west-2", name: "US West (Oregon)", city: "Oregon", continent: .northAmerica, flag: "🇺🇸"),
        AWSRegion(id: "ca-central-1", name: "Canada (Central)", city: "Montreal", continent: .northAmerica, flag: "🇨🇦"),
        AWSRegion(id: "ca-west-1", name: "Canada West (Calgary)", city: "Calgary", continent: .northAmerica, flag: "🇨🇦"),

        // South America
        AWSRegion(id: "sa-east-1", name: "South America (São Paulo)", city: "São Paulo", continent: .southAmerica, flag: "🇧🇷"),

        // Europe
        AWSRegion(id: "eu-west-1", name: "Europe (Ireland)", city: "Ireland", continent: .europe, flag: "🇮🇪"),
        AWSRegion(id: "eu-west-2", name: "Europe (London)", city: "London", continent: .europe, flag: "🇬🇧"),
        AWSRegion(id: "eu-west-3", name: "Europe (Paris)", city: "Paris", continent: .europe, flag: "🇫🇷"),
        AWSRegion(id: "eu-central-1", name: "Europe (Frankfurt)", city: "Frankfurt", continent: .europe, flag: "🇩🇪"),
        AWSRegion(id: "eu-central-2", name: "Europe (Zurich)", city: "Zurich", continent: .europe, flag: "🇨🇭"),
        AWSRegion(id: "eu-north-1", name: "Europe (Stockholm)", city: "Stockholm", continent: .europe, flag: "🇸🇪"),
        AWSRegion(id: "eu-south-1", name: "Europe (Milan)", city: "Milan", continent: .europe, flag: "🇮🇹"),
        AWSRegion(id: "eu-south-2", name: "Europe (Spain)", city: "Spain", continent: .europe, flag: "🇪🇸"),

        // Asia Pacific
        AWSRegion(id: "ap-northeast-1", name: "Asia Pacific (Tokyo)", city: "Tokyo", continent: .asia, flag: "🇯🇵"),
        AWSRegion(id: "ap-northeast-2", name: "Asia Pacific (Seoul)", city: "Seoul", continent: .asia, flag: "🇰🇷"),
        AWSRegion(id: "ap-northeast-3", name: "Asia Pacific (Osaka)", city: "Osaka", continent: .asia, flag: "🇯🇵"),
        AWSRegion(id: "ap-southeast-1", name: "Asia Pacific (Singapore)", city: "Singapore", continent: .asia, flag: "🇸🇬"),
        AWSRegion(id: "ap-southeast-2", name: "Asia Pacific (Sydney)", city: "Sydney", continent: .asia, flag: "🇦🇺"),
        AWSRegion(id: "ap-southeast-3", name: "Asia Pacific (Jakarta)", city: "Jakarta", continent: .asia, flag: "🇮🇩"),
        AWSRegion(id: "ap-southeast-4", name: "Asia Pacific (Melbourne)", city: "Melbourne", continent: .asia, flag: "🇦🇺"),
        AWSRegion(id: "ap-south-1", name: "Asia Pacific (Mumbai)", city: "Mumbai", continent: .asia, flag: "🇮🇳"),
        AWSRegion(id: "ap-south-2", name: "Asia Pacific (Hyderabad)", city: "Hyderabad", continent: .asia, flag: "🇮🇳"),
        AWSRegion(id: "ap-east-1", name: "Asia Pacific (Hong Kong)", city: "Hong Kong", continent: .asia, flag: "🇭🇰"),

        // Middle East
        AWSRegion(id: "me-south-1", name: "Middle East (Bahrain)", city: "Bahrain", continent: .middleEast, flag: "🇧🇭"),
        AWSRegion(id: "me-central-1", name: "Middle East (UAE)", city: "UAE", continent: .middleEast, flag: "🇦🇪"),
        AWSRegion(id: "il-central-1", name: "Israel (Tel Aviv)", city: "Tel Aviv", continent: .middleEast, flag: "🇮🇱"),

        // Africa
        AWSRegion(id: "af-south-1", name: "Africa (Cape Town)", city: "Cape Town", continent: .africa, flag: "🇿🇦"),
    ]

    /// Get region by ID
    public static func region(for id: String) -> AWSRegion? {
        allRegions.first { $0.id == id }
    }

    /// Get regions grouped by continent
    public static var regionsByContinent: [Continent: [AWSRegion]] {
        Dictionary(grouping: allRegions, by: { $0.continent })
    }

    /// Common regions (most frequently used)
    public static let commonRegions: [AWSRegion] = [
        region(for: "us-east-1")!,
        region(for: "us-west-2")!,
        region(for: "eu-west-1")!,
        region(for: "eu-central-1")!,
        region(for: "ap-northeast-1")!,
        region(for: "ap-southeast-1")!,
    ]
}

// MARK: - Region Latency Result

/// Result of a latency test to a specific region
public struct RegionLatencyResult: Identifiable, Sendable {
    public let id: String  // Region ID
    public let region: AWSRegion
    public let latencyMs: Double?
    public let status: Status
    public let testedAt: Date

    public enum Status: Sendable {
        case testing
        case success
        case failed(Error)
        case timeout
    }

    public init(region: AWSRegion, latencyMs: Double? = nil, status: Status = .testing, testedAt: Date = Date()) {
        self.id = region.id
        self.region = region
        self.latencyMs = latencyMs
        self.status = status
        self.testedAt = testedAt
    }

    public var latencyDescription: String {
        switch status {
        case .testing:
            return "Testing..."
        case .success:
            if let ms = latencyMs {
                return "\(Int(ms)) ms"
            }
            return "N/A"
        case .failed:
            return "Failed"
        case .timeout:
            return "Timeout"
        }
    }

    public var qualityRating: QualityRating {
        guard let ms = latencyMs else { return .unknown }
        switch ms {
        case ..<50: return .excellent
        case 50..<100: return .good
        case 100..<200: return .fair
        case 200..<500: return .poor
        default: return .bad
        }
    }

    public enum QualityRating: String, Sendable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case bad = "Bad"
        case unknown = "Unknown"

        public var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "green"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .bad: return "red"
            case .unknown: return "gray"
            }
        }

        public var iconName: String {
            switch self {
            case .excellent: return "wifi"
            case .good: return "wifi"
            case .fair: return "wifi.exclamationmark"
            case .poor: return "wifi.slash"
            case .bad: return "wifi.slash"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

// MARK: - Region Latency Service

/// Service for testing latency to AWS regions
public actor AWSRegionLatencyService {
    private var results: [String: RegionLatencyResult] = [:]
    private var testTasks: [String: Task<Void, Never>] = [:]
    private var updateCallback: (@Sendable ([RegionLatencyResult]) -> Void)?

    // S3 endpoint template for latency testing
    private let s3EndpointTemplate = "https://s3.%@.amazonaws.com"

    public init() {}

    // MARK: - Configuration

    public func setUpdateCallback(_ callback: @Sendable @escaping ([RegionLatencyResult]) -> Void) {
        self.updateCallback = callback
    }

    // MARK: - Latency Testing

    /// Test latency to a single region
    public func testLatency(to region: AWSRegion) async -> RegionLatencyResult {
        // Mark as testing
        let testingResult = RegionLatencyResult(region: region, status: .testing)
        results[region.id] = testingResult
        notifyUpdate()

        let endpoint = String(format: s3EndpointTemplate, region.id)
        guard let url = URL(string: endpoint) else {
            let failedResult = RegionLatencyResult(region: region, status: .failed(URLError(.badURL)))
            results[region.id] = failedResult
            notifyUpdate()
            return failedResult
        }

        // Perform multiple tests and average
        let testCount = 3
        var latencies: [Double] = []

        for _ in 0..<testCount {
            if let latency = await measureLatency(to: url) {
                latencies.append(latency)
            }
        }

        let result: RegionLatencyResult
        if latencies.isEmpty {
            result = RegionLatencyResult(region: region, status: .timeout)
        } else {
            let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
            result = RegionLatencyResult(region: region, latencyMs: avgLatency, status: .success)
        }

        results[region.id] = result
        notifyUpdate()
        return result
    }

    /// Test latency to all regions
    public func testAllRegions() async -> [RegionLatencyResult] {
        // Cancel any existing tests
        cancelAllTests()

        // Initialize all as testing
        for region in AWSRegion.allRegions {
            results[region.id] = RegionLatencyResult(region: region, status: .testing)
        }
        notifyUpdate()

        // Test all regions concurrently
        await withTaskGroup(of: RegionLatencyResult.self) { group in
            for region in AWSRegion.allRegions {
                group.addTask {
                    await self.testLatency(to: region)
                }
            }

            for await result in group {
                results[result.id] = result
            }
        }

        notifyUpdate()
        return Array(results.values).sorted { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
    }

    /// Test latency to common regions only (faster)
    public func testCommonRegions() async -> [RegionLatencyResult] {
        // Cancel any existing tests
        cancelAllTests()

        // Initialize common regions as testing
        for region in AWSRegion.commonRegions {
            results[region.id] = RegionLatencyResult(region: region, status: .testing)
        }
        notifyUpdate()

        // Test common regions concurrently
        await withTaskGroup(of: RegionLatencyResult.self) { group in
            for region in AWSRegion.commonRegions {
                group.addTask {
                    await self.testLatency(to: region)
                }
            }

            for await result in group {
                results[result.id] = result
            }
        }

        notifyUpdate()
        return Array(results.values).sorted { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
    }

    /// Get the best (lowest latency) region from tested results
    public func getBestRegion() -> AWSRegion? {
        results.values
            .filter { $0.latencyMs != nil }
            .min { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }?
            .region
    }

    /// Get all current results
    public func getResults() -> [RegionLatencyResult] {
        Array(results.values).sorted { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
    }

    /// Get result for a specific region
    public func getResult(for regionId: String) -> RegionLatencyResult? {
        results[regionId]
    }

    /// Cancel all ongoing tests
    public func cancelAllTests() {
        for (_, task) in testTasks {
            task.cancel()
        }
        testTasks.removeAll()
    }

    /// Clear all results
    public func clearResults() {
        cancelAllTests()
        results.removeAll()
        notifyUpdate()
    }

    // MARK: - Private Methods

    private func measureLatency(to url: URL) async -> Double? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"  // Just check connectivity, don't download
        request.timeoutInterval = 5.0

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let endTime = CFAbsoluteTimeGetCurrent()

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...499).contains(httpResponse.statusCode) else {
                return nil
            }

            return (endTime - startTime) * 1000  // Convert to milliseconds
        } catch {
            return nil
        }
    }

    private func notifyUpdate() {
        let sortedResults = Array(results.values).sorted { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
        updateCallback?(sortedResults)
    }
}

// MARK: - Cached Region Preferences

/// Stores user's region preferences and cached latency results
public struct RegionPreferences: Codable, Sendable {
    public var selectedRegionId: String?
    public var cachedLatencies: [String: CachedLatency]
    public var lastTestedAt: Date?
    public var autoSelectFastest: Bool

    public struct CachedLatency: Codable, Sendable {
        public let regionId: String
        public let latencyMs: Double
        public let testedAt: Date

        public var isStale: Bool {
            // Consider stale after 24 hours
            Date().timeIntervalSince(testedAt) > 86400
        }
    }

    public init(
        selectedRegionId: String? = nil,
        cachedLatencies: [String: CachedLatency] = [:],
        lastTestedAt: Date? = nil,
        autoSelectFastest: Bool = false
    ) {
        self.selectedRegionId = selectedRegionId
        self.cachedLatencies = cachedLatencies
        self.lastTestedAt = lastTestedAt
        self.autoSelectFastest = autoSelectFastest
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "ShotDropperRegionPreferences"

    public static func load() -> RegionPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(RegionPreferences.self, from: data) else {
            return RegionPreferences()
        }
        return prefs
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    /// Update cached latency for a region
    public mutating func updateCachedLatency(regionId: String, latencyMs: Double) {
        cachedLatencies[regionId] = CachedLatency(
            regionId: regionId,
            latencyMs: latencyMs,
            testedAt: Date()
        )
        lastTestedAt = Date()
    }

    /// Get the best region based on cached latencies
    public func getBestCachedRegion() -> String? {
        cachedLatencies.values
            .filter { !$0.isStale }
            .min { $0.latencyMs < $1.latencyMs }?
            .regionId
    }

    /// Check if cached data is stale
    public var isCacheStale: Bool {
        guard let lastTested = lastTestedAt else { return true }
        return Date().timeIntervalSince(lastTested) > 86400  // 24 hours
    }
}
