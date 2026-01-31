import XCTest
@testable import DragNDropCore

/// Integration tests that test the interaction between multiple components
final class IntegrationTests: XCTestCase {

    // MARK: - Workflow Pipeline Tests

    func testWorkflowExtractionPipeline() throws {
        // Create a sample workflow
        let workflow = WorkflowConfiguration(
            name: "Test VFX Workflow",
            bucket: "test-bucket",
            region: "us-east-1",
            pathTemplate: PathTemplate(
                template: "projects/{SHOW}/{EPISODE}/shots/{SHOT}/vfx/",
                placeholders: [
                    Placeholder(name: "SHOW"),
                    Placeholder(name: "EPISODE"),
                    Placeholder(name: "SHOT")
                ]
            ),
            extractionRules: [
                ExtractionRule(
                    name: "VFX Pattern",
                    pattern: "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)",
                    captureGroupMappings: [
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "SHOW"),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "EPISODE"),
                        CaptureGroupMapping(groupIndex: 3, placeholderName: "SHOT")
                    ]
                )
            ]
        )

        // Test filename extraction
        let filename = "MyShow_102_0010_comp_v003.nk"
        let extractedValues = workflow.extractionRules[0].extract(from: filename)

        XCTAssertNotNil(extractedValues)
        XCTAssertEqual(extractedValues?["SHOW"], "MyShow")
        XCTAssertEqual(extractedValues?["EPISODE"], "102")
        XCTAssertEqual(extractedValues?["SHOT"], "0010")

        // Build destination path
        if let values = extractedValues {
            let path = workflow.pathTemplate.buildPath(with: values)
            XCTAssertEqual(path, "projects/MyShow/102/shots/0010/vfx/")
        }
    }

    func testMultipleExtractionRulesPriority() {
        // Test that rules are applied in priority order
        let rules = [
            ExtractionRule(
                name: "Generic Pattern",
                priority: 0,
                pattern: "^([^_]+)",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "NAME")
                ]
            ),
            ExtractionRule(
                name: "Specific Pattern",
                priority: 1,
                pattern: "^([A-Za-z]+)_([0-9]+)",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "SHOW"),
                    CaptureGroupMapping(groupIndex: 2, placeholderName: "EPISODE")
                ]
            )
        ]

        let filename = "MyShow_102_test.nk"

        // Both should match, but specific pattern gives more info
        let genericResult = rules[0].extract(from: filename)
        let specificResult = rules[1].extract(from: filename)

        XCTAssertNotNil(genericResult)
        XCTAssertEqual(genericResult?["NAME"], "MyShow")

        XCTAssertNotNil(specificResult)
        XCTAssertEqual(specificResult?["SHOW"], "MyShow")
        XCTAssertEqual(specificResult?["EPISODE"], "102")
    }

    // MARK: - Upload Job Lifecycle Tests

    func testUploadJobLifecycle() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/test/file.nk"),
            destinationPath: "test/file.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "file.nk",
                fileExtension: "nk",
                size: 1024 * 1024,
                category: .nukeComp
            )
        )

        // Initial state
        XCTAssertEqual(job.status, .pending)
        XCTAssertNil(job.startedAt)
        XCTAssertNil(job.completedAt)
        XCTAssertEqual(job.retryAttempts, 0)

        // Start upload
        job.markStarted()
        XCTAssertEqual(job.status, .uploading)
        XCTAssertNotNil(job.startedAt)

        // Set total bytes first (as would happen in real upload)
        job.progress.totalBytes = 1024 * 1024

        // Simulate progress
        job.updateProgress(bytesUploaded: 512 * 1024)
        XCTAssertEqual(job.progress.bytesUploaded, 512 * 1024)
        XCTAssertEqual(job.progress.percentage, 50.0, accuracy: 0.1)

        // Complete
        job.markCompleted(presignedURL: "https://example.com/presigned")
        XCTAssertEqual(job.status, .completed)
        XCTAssertNotNil(job.completedAt)
        XCTAssertNotNil(job.presignedURL)
    }

    func testUploadJobRetryLifecycle() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/test/file.nk"),
            destinationPath: "test/file.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "file.nk",
                fileExtension: "nk",
                size: 1024,
                category: .nukeComp
            )
        )

        // Simulate failure
        let error = UploadError.networkError("Connection timeout")
        job.markFailed(error)
        XCTAssertEqual(job.status, .failed)
        XCTAssertNotNil(job.error)

        // Retry
        job.markForRetry(error: error)
        XCTAssertEqual(job.status, .pending)
        XCTAssertNil(job.error)
        XCTAssertEqual(job.retryAttempts, 1)
        XCTAssertEqual(job.retryErrors.count, 1)

        // Simulate another failure and retry
        job.markForRetry(error: UploadError.networkError("DNS failure"))
        XCTAssertEqual(job.retryAttempts, 2)
        XCTAssertEqual(job.retryErrors.count, 2)
    }

    // MARK: - File Filter Integration Tests

    func testFileFilterIntegration() {
        let filterService = FileFilterService()

        // Create config that allows only VFX files
        let config = FileFilterService.FilterConfig(
            enableFilter: true,
            allowedExtensions: ["nk", "exr", "mov"],
            blockedExtensions: ["exe", "dmg"],
            maxFileSizeMB: 0,
            allowHiddenFiles: false
        )

        // Test filtering logic
        XCTAssertTrue(config.allowedExtensions.contains("nk"))
        XCTAssertTrue(config.allowedExtensions.contains("exr"))
        XCTAssertFalse(config.allowedExtensions.contains("txt"))

        XCTAssertTrue(config.blockedExtensions.contains("exe"))
    }

    func testFileFilterPresets() {
        // Test preset extension lists
        let vfxAll = FileExtensionPreset.vfxAll.extensions
        XCTAssertTrue(vfxAll.count > 20)

        let nukeOnly = FileExtensionPreset.vfxNukeOnly.extensions
        XCTAssertTrue(nukeOnly.count < vfxAll.count)
        XCTAssertTrue(nukeOnly.contains("nk"))
        XCTAssertTrue(nukeOnly.contains("exr"))
    }

    // MARK: - Settings Persistence Tests

    func testSettingsCodable() throws {
        var settings = AppSettings()
        settings.awsSSOStartURL = "https://start.awsapps.com/start"
        settings.awsAccountId = "123456789012"
        settings.defaultUploadSettings.maxConcurrentUploads = 8
        settings.defaultUploadSettings.enableBandwidthThrottling = true
        settings.defaultUploadSettings.maxUploadSpeedMBps = 25.0

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.awsSSOStartURL, settings.awsSSOStartURL)
        XCTAssertEqual(decoded.awsAccountId, settings.awsAccountId)
        XCTAssertEqual(decoded.defaultUploadSettings.maxConcurrentUploads, 8)
        XCTAssertTrue(decoded.defaultUploadSettings.enableBandwidthThrottling)
        XCTAssertEqual(decoded.defaultUploadSettings.maxUploadSpeedMBps, 25.0)
    }

    // MARK: - Upload Settings Integration

    func testUploadSettingsIntegration() {
        var settings = UploadSettings()

        // Configure for high-speed network
        settings.maxConcurrentUploads = 8
        settings.multipartThresholdMB = 8
        settings.partSizeMB = 16
        settings.enableBandwidthThrottling = false

        XCTAssertEqual(settings.maxConcurrentUploads, 8)
        XCTAssertEqual(settings.multipartThresholdMB, 8)
        XCTAssertEqual(settings.partSizeMB, 16)
        XCTAssertFalse(settings.enableBandwidthThrottling)
        XCTAssertEqual(settings.maxUploadSpeedBps, 0)  // No throttling

        // Configure for throttled upload
        settings.enableBandwidthThrottling = true
        settings.maxUploadSpeedMBps = 10.0

        XCTAssertTrue(settings.enableBandwidthThrottling)
        XCTAssertEqual(settings.maxUploadSpeedBps, 10 * 1024 * 1024)
    }

    // MARK: - Throttle Schedule Integration

    func testThrottleScheduleIntegration() {
        let schedule = ThrottleSchedule(rules: [
            ThrottleRule(
                name: "Work Hours",
                startTimeMinutes: 9 * 60,   // 9:00 AM
                endTimeMinutes: 17 * 60,    // 5:00 PM
                speedLimitMBps: 5.0,
                daysOfWeek: Set(2...6)      // Mon-Fri
            ),
            ThrottleRule(
                name: "After Hours",
                startTimeMinutes: 17 * 60,  // 5:00 PM
                endTimeMinutes: 9 * 60,     // 9:00 AM (overnight)
                speedLimitMBps: 50.0,
                daysOfWeek: Set(2...6)      // Mon-Fri
            ),
            ThrottleRule(
                name: "Weekend",
                startTimeMinutes: 0,
                endTimeMinutes: 1440,       // All day
                speedLimitMBps: 100.0,
                daysOfWeek: Set([1, 7])     // Sun, Sat
            )
        ])

        XCTAssertEqual(schedule.rules.count, 3)

        // Test rule formatting
        let workRule = schedule.rules[0]
        XCTAssertEqual(workRule.startTimeString, "09:00")
        XCTAssertEqual(workRule.endTimeString, "17:00")
    }

    // MARK: - History Item Conversion Tests

    func testUploadHistoryItemConversion() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/Users/test/MyShow_102_0010_comp.nk"),
            destinationPath: "projects/MyShow/102/shots/0010/vfx/MyShow_102_0010_comp.nk",
            bucket: "vfx-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "MyShow_102_0010_comp.nk",
                fileExtension: "nk",
                size: 5 * 1024 * 1024,
                category: .nukeComp
            )
        )

        job.markStarted()
        job.markCompleted(presignedURL: "https://presigned.url")

        let historyItem = UploadHistoryItem.from(job: job)

        XCTAssertEqual(historyItem.id, job.id)
        XCTAssertEqual(historyItem.filename, "MyShow_102_0010_comp.nk")
        XCTAssertEqual(historyItem.bucket, "vfx-bucket")
        XCTAssertEqual(historyItem.region, "us-east-1")
        XCTAssertEqual(historyItem.status, .completed)
        XCTAssertNotNil(historyItem.completedAt)
        XCTAssertEqual(historyItem.s3URI, "s3://vfx-bucket/projects/MyShow/102/shots/0010/vfx/MyShow_102_0010_comp.nk")
    }

    // MARK: - Progress Formatting Tests

    func testProgressFormattingVariousUnits() {
        // Small file
        let small = UploadProgress(
            bytesUploaded: 512,
            totalBytes: 1024,
            percentage: 50.0
        )
        XCTAssertTrue(small.formattedBytesUploaded.contains("bytes") || small.formattedBytesUploaded.contains("KB"))

        // Medium file
        let medium = UploadProgress(
            bytesUploaded: 50 * 1024 * 1024,
            totalBytes: 100 * 1024 * 1024,
            percentage: 50.0,
            uploadSpeed: 10 * 1024 * 1024
        )
        XCTAssertTrue(medium.formattedBytesUploaded.contains("MB"))
        XCTAssertTrue(medium.formattedUploadSpeed.contains("MB"))

        // Large file
        let large = UploadProgress(
            bytesUploaded: 5 * 1024 * 1024 * 1024,
            totalBytes: 10 * 1024 * 1024 * 1024,
            percentage: 50.0
        )
        XCTAssertTrue(large.formattedBytesUploaded.contains("GB"))
    }

    // MARK: - Error Classification Tests

    func testErrorClassificationAndRetryability() {
        let errors: [(UploadError, Bool)] = [
            (.networkError("timeout"), true),
            (.networkError("connection refused"), true),
            (.unknown("something happened"), true),
            (.multipartUploadFailed("part 3 failed"), true),
            (.authenticationError("invalid token"), false),
            (.accessDenied("forbidden"), false),
            (.bucketNotFound("no such bucket"), false),
            (.cancelled, false),
            (.fileTooLarge("exceeds 5GB"), false)
        ]

        for (error, expectedRetryable) in errors {
            XCTAssertEqual(error.isRetryable, expectedRetryable, "Error \(error) retryability mismatch")
        }
    }

    // MARK: - File Category Tests

    func testFileCategoryAssignment() {
        let testCases: [(String, FileCategory)] = [
            ("nk", .nukeComp),
            ("nknc", .nukeComp),
            ("exr", .imageSequence),
            ("tif", .imageSequence),
            ("dpx", .imageSequence),
            ("mov", .video),
            ("mp4", .video),
            ("prores", .video),
            ("wav", .audio),
            ("aiff", .audio),
            ("aep", .project),
            ("blend", .project),
            ("unknown", .other)
        ]

        for (ext, expectedCategory) in testCases {
            let category = FileCategory.fromExtension(ext)
            XCTAssertEqual(category, expectedCategory, "Extension \(ext) should be \(expectedCategory)")
        }
    }

    // MARK: - Workflow Validation Tests

    func testWorkflowValidation() {
        // Valid workflow
        let validWorkflow = WorkflowConfiguration(
            name: "Valid Workflow",
            bucket: "my-bucket",
            region: "us-east-1",
            pathTemplate: PathTemplate(template: "uploads/{filename}")
        )

        XCTAssertFalse(validWorkflow.name.isEmpty)
        XCTAssertFalse(validWorkflow.bucket.isEmpty)
        XCTAssertFalse(validWorkflow.pathTemplate.template.isEmpty)

        // Sample workflow
        let sampleWorkflow = WorkflowConfiguration.sampleVFXWorkflow
        XCTAssertFalse(sampleWorkflow.extractionRules.isEmpty)
        XCTAssertEqual(sampleWorkflow.bucket, "sync-services")
    }

    // MARK: - Upload Schedule Tests

    func testUploadScheduleDisabled() {
        let schedule = UploadSchedule(isEnabled: false)
        XCTAssertTrue(schedule.isUploadAllowed())
    }

    func testUploadScheduleWithRules() {
        // Create a schedule that allows uploads during business hours
        let schedule = UploadSchedule(
            isEnabled: true,
            mode: .allowDuring,
            rules: [
                ScheduleRule(
                    name: "Business Hours",
                    startTimeMinutes: 9 * 60,   // 9 AM
                    endTimeMinutes: 17 * 60,    // 5 PM
                    daysOfWeek: Set(2...6)      // Mon-Fri
                )
            ]
        )

        XCTAssertEqual(schedule.rules.count, 1)
        XCTAssertEqual(schedule.rules[0].startTimeString, "09:00")
        XCTAssertEqual(schedule.rules[0].endTimeString, "17:00")
    }

    func testScheduleRuleTimeCheck() {
        // Rule from 9 AM to 5 PM
        let dayRule = ScheduleRule(
            name: "Day Rule",
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 17 * 60,
            daysOfWeek: Set(1...7)
        )

        // 10 AM should be within the rule
        XCTAssertTrue(dayRule.isTimeWithin(10 * 60))

        // 8 AM should be outside the rule
        XCTAssertFalse(dayRule.isTimeWithin(8 * 60))

        // 6 PM should be outside the rule
        XCTAssertFalse(dayRule.isTimeWithin(18 * 60))
    }

    func testScheduleRuleOvernightWindow() {
        // Rule from 6 PM to 9 AM (overnight)
        let nightRule = ScheduleRule(
            name: "Night Rule",
            startTimeMinutes: 18 * 60,  // 6 PM
            endTimeMinutes: 9 * 60,     // 9 AM
            daysOfWeek: Set(1...7)
        )

        // 10 PM should be within the rule
        XCTAssertTrue(nightRule.isTimeWithin(22 * 60))

        // 3 AM should be within the rule
        XCTAssertTrue(nightRule.isTimeWithin(3 * 60))

        // 12 PM (noon) should be outside the rule
        XCTAssertFalse(nightRule.isTimeWithin(12 * 60))
    }

    func testSchedulePresets() {
        // Off hours preset
        let offHours = UploadSchedule.offHoursOnly
        XCTAssertTrue(offHours.isEnabled)
        XCTAssertEqual(offHours.mode, .allowDuring)
        XCTAssertEqual(offHours.rules.count, 2)

        // Business hours preset
        let businessHours = UploadSchedule.businessHoursOnly
        XCTAssertTrue(businessHours.isEnabled)
        XCTAssertEqual(businessHours.mode, .allowDuring)
        XCTAssertEqual(businessHours.rules.count, 1)
    }

    func testScheduleRuleDaysDescription() {
        // Weekdays
        let weekdayRule = ScheduleRule(
            name: "Test",
            startTimeMinutes: 0,
            endTimeMinutes: 1440,
            daysOfWeek: Set(2...6)
        )
        XCTAssertEqual(weekdayRule.daysDescription, "Weekdays")

        // Weekends
        let weekendRule = ScheduleRule(
            name: "Test",
            startTimeMinutes: 0,
            endTimeMinutes: 1440,
            daysOfWeek: Set([1, 7])
        )
        XCTAssertEqual(weekendRule.daysDescription, "Weekends")

        // Every day
        let everydayRule = ScheduleRule(
            name: "Test",
            startTimeMinutes: 0,
            endTimeMinutes: 1440,
            daysOfWeek: Set(1...7)
        )
        XCTAssertEqual(everydayRule.daysDescription, "Every day")
    }

    func testSchedulePresetEnumeration() {
        // Verify all presets exist and have valid descriptions
        for preset in SchedulePreset.allCases {
            XCTAssertFalse(preset.description.isEmpty)

            // Custom preset returns nil schedule
            if preset == .custom {
                XCTAssertNil(preset.schedule)
            } else {
                XCTAssertNotNil(preset.schedule)
            }
        }
    }

    // MARK: - AWS Region Tests

    func testAWSRegionLookup() {
        // Test region lookup by ID
        let usEast1 = AWSRegion.region(for: "us-east-1")
        XCTAssertNotNil(usEast1)
        XCTAssertEqual(usEast1?.name, "US East (N. Virginia)")
        XCTAssertEqual(usEast1?.continent, .northAmerica)
        XCTAssertEqual(usEast1?.flag, "🇺🇸")

        // Test invalid region
        let invalid = AWSRegion.region(for: "invalid-region")
        XCTAssertNil(invalid)
    }

    func testAWSRegionsByContinent() {
        // Get regions grouped by continent
        let regionsByContinent = AWSRegion.regionsByContinent

        // Check each continent has regions
        XCTAssertFalse(regionsByContinent[.northAmerica]?.isEmpty ?? true)
        XCTAssertFalse(regionsByContinent[.europe]?.isEmpty ?? true)
        XCTAssertFalse(regionsByContinent[.asia]?.isEmpty ?? true)
        XCTAssertFalse(regionsByContinent[.southAmerica]?.isEmpty ?? true)

        // Verify US regions are in North America
        let northAmerica = regionsByContinent[.northAmerica] ?? []
        XCTAssertTrue(northAmerica.contains { $0.id == "us-east-1" })
        XCTAssertTrue(northAmerica.contains { $0.id == "us-west-2" })
        XCTAssertTrue(northAmerica.contains { $0.id == "ca-central-1" })
    }

    func testAWSRegionCommonRegions() {
        // Verify common regions list
        XCTAssertFalse(AWSRegion.commonRegions.isEmpty)
        XCTAssertTrue(AWSRegion.commonRegions.count >= 4)

        // Common regions should include major ones
        let commonIds = AWSRegion.commonRegions.map { $0.id }
        XCTAssertTrue(commonIds.contains("us-east-1"))
        XCTAssertTrue(commonIds.contains("eu-west-1"))
    }

    func testAWSRegionAllRegionsComplete() {
        // Verify all regions have required data
        for region in AWSRegion.allRegions {
            XCTAssertFalse(region.id.isEmpty, "Region ID should not be empty")
            XCTAssertFalse(region.name.isEmpty, "Region name should not be empty")
            XCTAssertFalse(region.city.isEmpty, "Region city should not be empty")
            XCTAssertFalse(region.flag.isEmpty, "Region flag should not be empty")
        }

        // Verify no duplicate IDs
        let ids = AWSRegion.allRegions.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Region IDs should be unique")
    }

    func testLatencyQualityRating() {
        let region = AWSRegion.region(for: "us-east-1")!

        // Test excellent latency
        let excellent = RegionLatencyResult(region: region, latencyMs: 30, status: .success)
        XCTAssertEqual(excellent.qualityRating, .excellent)

        // Test good latency
        let good = RegionLatencyResult(region: region, latencyMs: 75, status: .success)
        XCTAssertEqual(good.qualityRating, .good)

        // Test fair latency
        let fair = RegionLatencyResult(region: region, latencyMs: 150, status: .success)
        XCTAssertEqual(fair.qualityRating, .fair)

        // Test poor latency
        let poor = RegionLatencyResult(region: region, latencyMs: 350, status: .success)
        XCTAssertEqual(poor.qualityRating, .poor)

        // Test bad latency
        let bad = RegionLatencyResult(region: region, latencyMs: 600, status: .success)
        XCTAssertEqual(bad.qualityRating, .bad)

        // Test unknown (no latency)
        let unknown = RegionLatencyResult(region: region, status: .testing)
        XCTAssertEqual(unknown.qualityRating, .unknown)
    }

    func testLatencyResultDescription() {
        let region = AWSRegion.region(for: "us-east-1")!

        // Testing status
        let testing = RegionLatencyResult(region: region, status: .testing)
        XCTAssertEqual(testing.latencyDescription, "Testing...")

        // Success status
        let success = RegionLatencyResult(region: region, latencyMs: 42.5, status: .success)
        XCTAssertEqual(success.latencyDescription, "42 ms")

        // Timeout status
        let timeout = RegionLatencyResult(region: region, status: .timeout)
        XCTAssertEqual(timeout.latencyDescription, "Timeout")
    }

    func testRegionPreferencesPersistence() {
        var prefs = RegionPreferences(selectedRegionId: "eu-west-1")
        prefs.updateCachedLatency(regionId: "us-east-1", latencyMs: 50)
        prefs.updateCachedLatency(regionId: "eu-west-1", latencyMs: 30)

        // Test best cached region
        let best = prefs.getBestCachedRegion()
        XCTAssertEqual(best, "eu-west-1")  // 30ms is lower

        // Test cache staleness
        XCTAssertFalse(prefs.isCacheStale)
    }

    func testRegionContinentEnumeration() {
        // Verify all continents are represented
        for continent in AWSRegion.Continent.allCases {
            XCTAssertFalse(continent.rawValue.isEmpty)
            let regions = AWSRegion.regionsByContinent[continent] ?? []
            // At least middle east and africa might have just 1-2 regions
            XCTAssertFalse(regions.isEmpty, "\(continent.rawValue) should have at least one region")
        }
    }
}
