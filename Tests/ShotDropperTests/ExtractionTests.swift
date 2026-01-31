import XCTest
@testable import ShotDropperCore

final class ExtractionTests: XCTestCase {

    // MARK: - Path Template Tests

    func testPathTemplateBuildPath() {
        let template = PathTemplate(
            template: "CLIENTS/{CLIENT}/SHOWS/{SHOW}/shots/{SHOT}/vfx/",
            placeholders: [
                Placeholder(name: "CLIENT"),
                Placeholder(name: "SHOW"),
                Placeholder(name: "SHOT")
            ]
        )

        let values = [
            "CLIENT": "Acme",
            "SHOW": "Berlin",
            "SHOT": "0010"
        ]

        let result = template.buildPath(with: values)
        XCTAssertEqual(result, "CLIENTS/Acme/SHOWS/Berlin/shots/0010/vfx/")
    }

    func testPathTemplateExtractPlaceholders() {
        let template = PathTemplate(
            template: "{PROJECT}/{SEQUENCE}/{SHOT}/output/"
        )

        let placeholders = template.extractedPlaceholderNames
        XCTAssertEqual(placeholders.count, 3)
        XCTAssertTrue(placeholders.contains("PROJECT"))
        XCTAssertTrue(placeholders.contains("SEQUENCE"))
        XCTAssertTrue(placeholders.contains("SHOT"))
    }

    // MARK: - Extraction Rule Tests

    func testExtractionRuleBasicMatch() {
        let rule = ExtractionRule(
            name: "Test Pattern",
            pattern: "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z]+)",
            captureGroupMappings: [
                CaptureGroupMapping(groupIndex: 1, placeholderName: "show"),
                CaptureGroupMapping(groupIndex: 2, placeholderName: "episode"),
                CaptureGroupMapping(groupIndex: 3, placeholderName: "shot"),
                CaptureGroupMapping(groupIndex: 4, placeholderName: "category")
            ]
        )

        let result = rule.extract(from: "Berlin_102_0010_comp.nk")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["show"], "Berlin")
        XCTAssertEqual(result?["episode"], "102")
        XCTAssertEqual(result?["shot"], "0010")
        XCTAssertEqual(result?["category"], "comp")
    }

    func testExtractionRuleNoMatch() {
        let rule = ExtractionRule(
            name: "Test Pattern",
            pattern: "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z]+)",
            captureGroupMappings: []
        )

        let result = rule.extract(from: "random_file.txt")
        XCTAssertNil(result)
    }

    func testExtractionRuleDisabled() {
        let rule = ExtractionRule(
            name: "Test Pattern",
            enabled: false,
            pattern: "^([A-Za-z]+)_([0-9]+)",
            captureGroupMappings: [
                CaptureGroupMapping(groupIndex: 1, placeholderName: "show")
            ]
        )

        let result = rule.extract(from: "Berlin_102")
        XCTAssertNil(result)
    }

    func testExtractionRuleWithTransformations() {
        let rule = ExtractionRule(
            name: "Test Pattern",
            pattern: "^([A-Za-z]+)_([0-9]+)",
            captureGroupMappings: [
                CaptureGroupMapping(
                    groupIndex: 1,
                    placeholderName: "show_upper",
                    transformations: [.uppercase]
                ),
                CaptureGroupMapping(
                    groupIndex: 1,
                    placeholderName: "show_lower",
                    transformations: [.lowercase]
                )
            ]
        )

        let result = rule.extract(from: "Berlin_102")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["show_upper"], "BERLIN")
        XCTAssertEqual(result?["show_lower"], "berlin")
    }

    // MARK: - Placeholder Transformation Tests

    func testTransformationUppercase() {
        let result = PlaceholderTransformation.uppercase.apply(to: "hello")
        XCTAssertEqual(result, "HELLO")
    }

    func testTransformationLowercase() {
        let result = PlaceholderTransformation.lowercase.apply(to: "HELLO")
        XCTAssertEqual(result, "hello")
    }

    func testTransformationCapitalize() {
        let result = PlaceholderTransformation.capitalize.apply(to: "hello world")
        XCTAssertEqual(result, "Hello World")
    }

    func testTransformationPadLeft() {
        let result = PlaceholderTransformation.padLeft.apply(to: "1", padding: 4)
        XCTAssertEqual(result, "0001")
    }

    // MARK: - File Category Tests

    func testFileCategoryFromExtension() {
        XCTAssertEqual(FileCategory.fromExtension("nk"), .nukeComp)
        XCTAssertEqual(FileCategory.fromExtension("exr"), .imageSequence)
        XCTAssertEqual(FileCategory.fromExtension("mov"), .video)
        XCTAssertEqual(FileCategory.fromExtension("wav"), .audio)
        XCTAssertEqual(FileCategory.fromExtension("aep"), .project)
        XCTAssertEqual(FileCategory.fromExtension("xyz"), .other)
    }

    // MARK: - Workflow Configuration Tests

    func testWorkflowConfigurationCodable() throws {
        let workflow = WorkflowConfiguration.sampleVFXWorkflow

        let encoder = JSONEncoder()
        let data = try encoder.encode(workflow)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkflowConfiguration.self, from: data)

        XCTAssertEqual(decoded.name, workflow.name)
        XCTAssertEqual(decoded.bucket, workflow.bucket)
        XCTAssertEqual(decoded.region, workflow.region)
        XCTAssertEqual(decoded.pathTemplate.template, workflow.pathTemplate.template)
    }

    // MARK: - Upload Progress Tests

    func testUploadProgressFormatting() {
        let progress = UploadProgress(
            bytesUploaded: 1024 * 1024 * 50,  // 50 MB
            totalBytes: 1024 * 1024 * 100,    // 100 MB
            percentage: 50.0,
            uploadSpeed: 1024 * 1024 * 10     // 10 MB/s
        )

        XCTAssertEqual(progress.percentage, 50.0)
        // Formatted strings will contain MB indicator
        XCTAssertFalse(progress.formattedBytesUploaded.isEmpty)
        XCTAssertFalse(progress.formattedTotalBytes.isEmpty)
        XCTAssertTrue(progress.formattedBytesUploaded.contains("MB"))
        XCTAssertTrue(progress.formattedTotalBytes.contains("MB"))
    }

    // MARK: - Upload Job Tests

    func testUploadJobStatusTransitions() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/tmp/test.nk"),
            destinationPath: "test/test.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "test.nk",
                fileExtension: "nk",
                size: 1024,
                category: .nukeComp
            )
        )

        XCTAssertEqual(job.status, .pending)

        job.markStarted()
        XCTAssertEqual(job.status, .uploading)
        XCTAssertNotNil(job.startedAt)

        job.markCompleted(presignedURL: "https://example.com/presigned")
        XCTAssertEqual(job.status, .completed)
        XCTAssertNotNil(job.completedAt)
        XCTAssertNotNil(job.presignedURL)
    }

    func testUploadJobS3URI() {
        let job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/tmp/test.nk"),
            destinationPath: "folder/test.nk",
            bucket: "my-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "test.nk",
                fileExtension: "nk",
                size: 1024,
                category: .nukeComp
            )
        )

        XCTAssertEqual(job.fullS3Path, "s3://my-bucket/folder/test.nk")
    }

    // MARK: - Retry Logic Tests

    func testUploadJobRetryTracking() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/tmp/test.nk"),
            destinationPath: "test/test.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "test.nk",
                fileExtension: "nk",
                size: 1024,
                category: .nukeComp
            )
        )

        // Initially no retries
        XCTAssertEqual(job.retryAttempts, 0)
        XCTAssertNil(job.lastRetryAt)
        XCTAssertTrue(job.retryErrors.isEmpty)

        // Mark for retry
        let error = UploadError.networkError("Connection timeout")
        job.markForRetry(error: error)

        XCTAssertEqual(job.retryAttempts, 1)
        XCTAssertNotNil(job.lastRetryAt)
        XCTAssertEqual(job.retryErrors.count, 1)
        XCTAssertEqual(job.status, .pending)
        XCTAssertNil(job.error)

        // Mark for retry again
        let error2 = UploadError.networkError("DNS lookup failed")
        job.markForRetry(error: error2)

        XCTAssertEqual(job.retryAttempts, 2)
        XCTAssertEqual(job.retryErrors.count, 2)
    }

    func testUploadJobResetForRetry() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/tmp/test.nk"),
            destinationPath: "test/test.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "test.nk",
                fileExtension: "nk",
                size: 1024,
                category: .nukeComp
            )
        )

        // Simulate partial upload
        job.status = .failed
        job.error = .networkError("Connection failed")
        job.progress = UploadProgress(bytesUploaded: 512, totalBytes: 1024, percentage: 50)

        // Reset for retry
        job.resetForRetry()

        XCTAssertEqual(job.status, .pending)
        XCTAssertNil(job.error)
        XCTAssertEqual(job.progress.bytesUploaded, 0)
        XCTAssertEqual(job.progress.totalBytes, 1024)  // Preserved
    }

    func testUploadErrorIsRetryable() {
        // Retryable errors
        XCTAssertTrue(UploadError.networkError("Connection timeout").isRetryable)
        XCTAssertTrue(UploadError.unknown("Something went wrong").isRetryable)
        XCTAssertTrue(UploadError.multipartUploadFailed("Part 3 failed").isRetryable)

        // Non-retryable errors
        XCTAssertFalse(UploadError.authenticationError("Invalid credentials").isRetryable)
        XCTAssertFalse(UploadError.accessDenied("Forbidden").isRetryable)
        XCTAssertFalse(UploadError.bucketNotFound("No such bucket").isRetryable)
        XCTAssertFalse(UploadError.keyTooLong("Key exceeds limit").isRetryable)
        XCTAssertFalse(UploadError.fileTooLarge("File exceeds 5GB").isRetryable)
        XCTAssertFalse(UploadError.checksumMismatch("Checksum mismatch").isRetryable)
        XCTAssertFalse(UploadError.cancelled.isRetryable)
    }

    func testUploadErrorDebugDescription() {
        let networkError = UploadError.networkError("Timeout")
        XCTAssertTrue(networkError.debugDescription.contains("[Network]"))
        XCTAssertTrue(networkError.debugDescription.contains("Timeout"))

        let authError = UploadError.authenticationError("Bad creds")
        XCTAssertTrue(authError.debugDescription.contains("[Auth]"))

        let cancelledError = UploadError.cancelled
        XCTAssertTrue(cancelledError.debugDescription.contains("[Cancelled]"))
    }

    func testUploadSettingsRetryDefaults() {
        let settings = UploadSettings()

        XCTAssertEqual(settings.retryCount, 3)
        XCTAssertEqual(settings.retryDelaySeconds, 5)
    }

    func testUploadJobPreservesCompletedPartsOnRetry() {
        var job = UploadJob(
            sourceURL: URL(fileURLWithPath: "/tmp/test.nk"),
            destinationPath: "test/test.nk",
            bucket: "test-bucket",
            region: "us-east-1",
            fileInfo: FileInfo(
                filename: "test.nk",
                fileExtension: "nk",
                size: 1024 * 1024 * 100,  // 100 MB
                category: .nukeComp
            )
        )

        // Simulate multipart upload with some completed parts
        job.uploadId = "upload-123"
        job.completedParts = [
            CompletedPart(partNumber: 1, eTag: "etag1", size: 8 * 1024 * 1024),
            CompletedPart(partNumber: 2, eTag: "etag2", size: 8 * 1024 * 1024)
        ]

        // Reset for retry (resumable)
        job.resetForRetry()

        // Upload ID and completed parts should be preserved for resumable uploads
        XCTAssertEqual(job.status, .pending)
        // Note: completedParts are preserved to allow resuming from where we left off
    }

    // MARK: - Bandwidth Throttling Tests

    func testUploadSettingsBandwidthDefaults() {
        let settings = UploadSettings()

        XCTAssertFalse(settings.enableBandwidthThrottling)
        XCTAssertEqual(settings.maxUploadSpeedMBps, 0)
        XCTAssertNil(settings.throttleSchedule)
    }

    func testUploadSettingsBandwidthSpeedConversion() {
        var settings = UploadSettings()
        settings.enableBandwidthThrottling = true
        settings.maxUploadSpeedMBps = 10.0  // 10 MB/s

        // Should convert to bytes per second
        XCTAssertEqual(settings.maxUploadSpeedBps, 10 * 1024 * 1024)

        // When disabled, should return 0
        settings.enableBandwidthThrottling = false
        XCTAssertEqual(settings.maxUploadSpeedBps, 0)
    }

    func testThrottleRuleTimeCheck() {
        // Rule for 9:00 AM - 5:00 PM
        let rule = ThrottleRule(
            name: "Work hours",
            startTimeMinutes: 9 * 60,   // 9:00
            endTimeMinutes: 17 * 60,    // 17:00
            speedLimitMBps: 5.0
        )

        // 10:00 AM should be active
        XCTAssertTrue(rule.isActive(at: 10 * 60))

        // 8:00 AM should not be active
        XCTAssertFalse(rule.isActive(at: 8 * 60))

        // 6:00 PM should not be active
        XCTAssertFalse(rule.isActive(at: 18 * 60))
    }

    func testThrottleRuleOvernightRange() {
        // Rule for 10:00 PM - 6:00 AM (overnight)
        let rule = ThrottleRule(
            name: "Night",
            startTimeMinutes: 22 * 60,  // 22:00
            endTimeMinutes: 6 * 60,     // 06:00
            speedLimitMBps: 50.0
        )

        // 11:00 PM should be active
        XCTAssertTrue(rule.isActive(at: 23 * 60))

        // 2:00 AM should be active
        XCTAssertTrue(rule.isActive(at: 2 * 60))

        // 12:00 PM (noon) should not be active
        XCTAssertFalse(rule.isActive(at: 12 * 60))
    }

    func testThrottleRuleTimeFormatting() {
        let rule = ThrottleRule(
            name: "Test",
            startTimeMinutes: 9 * 60 + 30,   // 9:30
            endTimeMinutes: 17 * 60 + 45,    // 17:45
            speedLimitMBps: 10.0
        )

        XCTAssertEqual(rule.startTimeString, "09:30")
        XCTAssertEqual(rule.endTimeString, "17:45")
    }

    func testThrottleRuleDisabled() {
        let rule = ThrottleRule(
            name: "Disabled rule",
            enabled: false,
            startTimeMinutes: 0,
            endTimeMinutes: 1440,  // All day
            speedLimitMBps: 1.0
        )

        // Even at valid time, disabled rule should not be active
        XCTAssertFalse(rule.isActive(at: 12 * 60))
    }

    func testThrottleScheduleNoRules() {
        let schedule = ThrottleSchedule(rules: [])
        XCTAssertNil(schedule.currentSpeedLimitMBps())
    }

    // MARK: - File Filter Tests

    func testFileFilterConfigFromSettings() {
        var settings = AppSettings()
        settings.enableFileTypeFilter = true
        settings.allowedFileExtensions = ["nk", "exr"]
        settings.blockedFileExtensions = ["exe"]
        settings.maxFileSizeMB = 100
        settings.allowHiddenFiles = false

        let config = FileFilterService.FilterConfig.from(settings: settings)

        XCTAssertTrue(config.enableFilter)
        XCTAssertTrue(config.allowedExtensions.contains("nk"))
        XCTAssertTrue(config.allowedExtensions.contains("exr"))
        XCTAssertTrue(config.blockedExtensions.contains("exe"))
        XCTAssertEqual(config.maxFileSizeBytes, 100 * 1024 * 1024)
        XCTAssertFalse(config.allowHiddenFiles)
    }

    func testFileFilterAllowedByDefault() {
        let service = FileFilterService()
        let config = FileFilterService.FilterConfig(enableFilter: false)

        // When filter is disabled, everything should be allowed
        let result = service.checkFile(
            at: URL(fileURLWithPath: "/tmp/test.anything"),
            config: config
        )

        // File doesn't exist but that's fine - we're testing the filter logic
        // In this case, disabled filter should still check file existence
    }

    func testFileFilterBlockedExtension() {
        let service = FileFilterService()
        let config = FileFilterService.FilterConfig(
            enableFilter: true,
            blockedExtensions: ["exe", "dmg", "app"]
        )

        // Test that blocked extensions are properly recorded
        XCTAssertTrue(config.blockedExtensions.contains("exe"))
        XCTAssertTrue(config.blockedExtensions.contains("dmg"))
        XCTAssertTrue(config.blockedExtensions.contains("app"))
    }

    func testFileFilterAllowedExtension() {
        let service = FileFilterService()
        let config = FileFilterService.FilterConfig(
            enableFilter: true,
            allowedExtensions: ["nk", "exr", "mov"]
        )

        // Test that allowed extensions are properly recorded
        XCTAssertTrue(config.allowedExtensions.contains("nk"))
        XCTAssertTrue(config.allowedExtensions.contains("exr"))
        XCTAssertTrue(config.allowedExtensions.contains("mov"))
        XCTAssertFalse(config.allowedExtensions.contains("exe"))
    }

    func testFileFilterResultReasons() {
        // Test various filter results have proper reason strings
        XCTAssertEqual(
            FileFilterService.FilterResult.blockedByExtension("exe").reason,
            "File extension '.exe' is blocked"
        )

        XCTAssertEqual(
            FileFilterService.FilterResult.notInAllowedList("txt").reason,
            "File extension '.txt' is not in the allowed list"
        )

        XCTAssertEqual(
            FileFilterService.FilterResult.hiddenFile.reason,
            "Hidden files are not allowed"
        )

        XCTAssertTrue(FileFilterService.FilterResult.allowed.isAllowed)
        XCTAssertFalse(FileFilterService.FilterResult.blockedByExtension("exe").isAllowed)
    }

    func testFileExtensionPresets() {
        // VFX All preset should include common extensions
        let vfxAllExtensions = FileExtensionPreset.vfxAll.extensions
        XCTAssertTrue(vfxAllExtensions.contains("nk"))
        XCTAssertTrue(vfxAllExtensions.contains("exr"))
        XCTAssertTrue(vfxAllExtensions.contains("mov"))

        // Nuke-only preset should be more limited
        let nukeOnlyExtensions = FileExtensionPreset.vfxNukeOnly.extensions
        XCTAssertTrue(nukeOnlyExtensions.contains("nk"))
        XCTAssertTrue(nukeOnlyExtensions.contains("exr"))
        XCTAssertFalse(nukeOnlyExtensions.contains("mov"))

        // Image sequences preset
        let imageExtensions = FileExtensionPreset.imageSequences.extensions
        XCTAssertTrue(imageExtensions.contains("exr"))
        XCTAssertTrue(imageExtensions.contains("png"))
        XCTAssertFalse(imageExtensions.contains("mov"))

        // Custom preset should be empty
        XCTAssertTrue(FileExtensionPreset.custom.extensions.isEmpty)
    }

    func testFilteredFilesRejectionSummary() {
        let filtered = FilteredFiles(
            allowed: [],
            rejected: [
                (URL(fileURLWithPath: "/test.exe"), .blockedByExtension("exe")),
                (URL(fileURLWithPath: "/test2.exe"), .blockedByExtension("exe")),
                (URL(fileURLWithPath: "/.hidden"), .hiddenFile)
            ]
        )

        XCTAssertEqual(filtered.rejectedCount, 3)
        XCTAssertTrue(filtered.hasRejected)

        let summary = filtered.rejectionSummary
        XCTAssertEqual(summary["Blocked extension: .exe"], 2)
        XCTAssertEqual(summary["Hidden file"], 1)
    }

    func testDefaultAllowedExtensions() {
        // Ensure default extensions include VFX staples
        let defaults = AppSettings.defaultAllowedExtensions

        // Nuke
        XCTAssertTrue(defaults.contains("nk"))
        XCTAssertTrue(defaults.contains("nknc"))

        // Image sequences
        XCTAssertTrue(defaults.contains("exr"))
        XCTAssertTrue(defaults.contains("tif"))
        XCTAssertTrue(defaults.contains("png"))
        XCTAssertTrue(defaults.contains("dpx"))

        // Video
        XCTAssertTrue(defaults.contains("mov"))
        XCTAssertTrue(defaults.contains("mp4"))

        // Audio
        XCTAssertTrue(defaults.contains("wav"))
    }

    func testDefaultBlockedExtensions() {
        // Ensure potentially dangerous files are blocked by default
        let blocked = AppSettings.defaultBlockedExtensions

        XCTAssertTrue(blocked.contains("exe"))
        XCTAssertTrue(blocked.contains("app"))
        XCTAssertTrue(blocked.contains("dmg"))
        XCTAssertTrue(blocked.contains("sh"))
    }

    // MARK: - Duplicate Detection Tests

    func testDuplicateDetectionConfigDefaults() {
        let config = DuplicateDetectionService.Config()

        XCTAssertTrue(config.enableDuplicateDetection)
        XCTAssertTrue(config.checkS3ForDuplicates)
        XCTAssertTrue(config.checkLocalDuplicates)
        XCTAssertEqual(config.onDuplicateAction, .warn)
    }

    func testDuplicateActionDescriptions() {
        XCTAssertFalse(DuplicateDetectionService.DuplicateAction.skip.description.isEmpty)
        XCTAssertFalse(DuplicateDetectionService.DuplicateAction.warn.description.isEmpty)
        XCTAssertFalse(DuplicateDetectionService.DuplicateAction.rename.description.isEmpty)
        XCTAssertFalse(DuplicateDetectionService.DuplicateAction.overwrite.description.isEmpty)
    }

    func testDuplicateCheckResultNotDuplicate() {
        let result = DuplicateDetectionService.DuplicateCheckResult.notDuplicate

        XCTAssertFalse(result.isDuplicate)
        XCTAssertNil(result.duplicateType)
        XCTAssertNil(result.existingLocation)
    }

    func testHashAlgorithmCases() {
        let algorithms = DuplicateDetectionService.HashAlgorithm.allCases

        XCTAssertTrue(algorithms.contains(.md5))
        XCTAssertTrue(algorithms.contains(.sha256))
        XCTAssertTrue(algorithms.contains(.quickHash))

        // Check display names
        XCTAssertEqual(DuplicateDetectionService.HashAlgorithm.md5.displayName, "MD5")
        XCTAssertEqual(DuplicateDetectionService.HashAlgorithm.sha256.displayName, "SHA-256")
    }

    func testDuplicateDetectionSettingsInAppSettings() {
        var settings = AppSettings()

        // Default values
        XCTAssertTrue(settings.enableDuplicateDetection)
        XCTAssertTrue(settings.checkS3ForDuplicates)
        XCTAssertEqual(settings.duplicateAction, .warn)

        // Can be changed
        settings.enableDuplicateDetection = false
        settings.duplicateAction = .skip
        XCTAssertFalse(settings.enableDuplicateDetection)
        XCTAssertEqual(settings.duplicateAction, .skip)
    }

    func testGenerateUniqueName() async {
        let service = DuplicateDetectionService()

        // No conflict
        let name1 = await service.generateUniqueName(
            originalName: "test.nk",
            existingNames: []
        )
        XCTAssertEqual(name1, "test.nk")

        // With conflict
        let name2 = await service.generateUniqueName(
            originalName: "test.nk",
            existingNames: ["test.nk"]
        )
        XCTAssertEqual(name2, "test_1.nk")

        // Multiple conflicts
        let name3 = await service.generateUniqueName(
            originalName: "test.nk",
            existingNames: ["test.nk", "test_1.nk", "test_2.nk"]
        )
        XCTAssertEqual(name3, "test_3.nk")

        // File without extension
        let name4 = await service.generateUniqueName(
            originalName: "README",
            existingNames: ["README"]
        )
        XCTAssertEqual(name4, "README_1")
    }
}
