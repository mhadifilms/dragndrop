import Foundation
import UserNotifications
import Logging

// MARK: - Notification Service

/// Manages system notifications for upload events
public actor NotificationService {
    private let logger = Logger(label: "com.dragndrop.notifications")

    private var isEnabled: Bool = true
    private var playSound: Bool = true
    private var isAvailable: Bool = false

    public init() {
        // Check if we're running in a proper app bundle context
        // UNUserNotificationCenter requires running from a .app bundle
        let bundlePath = Bundle.main.bundlePath
        self.isAvailable = bundlePath.hasSuffix(".app")
    }

    // MARK: - Configuration

    public func configure(enabled: Bool, sound: Bool) {
        self.isEnabled = enabled
        self.playSound = sound
    }

    // MARK: - Authorization

    public func requestAuthorization() async throws -> Bool {
        guard isAvailable else {
            logger.warning("Notifications unavailable - not running in app bundle")
            return false
        }

        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        logger.info("Notification authorization: \(granted)")
        return granted
    }

    public func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        guard isAvailable else { return .notDetermined }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Notifications

    /// Notifies that an upload has started
    public func notifyUploadStarted(job: UploadJob) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upload Started"
        content.body = "Uploading \(job.displayName)"
        content.categoryIdentifier = "UPLOAD_PROGRESS"

        await send(content: content, identifier: "start-\(job.id)")
    }

    /// Notifies that an upload has completed
    public func notifyUploadCompleted(job: UploadJob) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body = "\(job.displayName) uploaded successfully"
        content.categoryIdentifier = "UPLOAD_COMPLETE"

        if playSound {
            content.sound = .default
        }

        // Add actions
        content.userInfo = [
            "jobId": job.id.uuidString,
            "s3uri": job.fullS3Path,
            "bucket": job.bucket,
            "key": job.destinationPath
        ]

        await send(content: content, identifier: "complete-\(job.id)")
    }

    /// Notifies that an upload has failed
    public func notifyUploadFailed(job: UploadJob) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upload Failed"
        content.body = "\(job.displayName): \(job.error?.localizedDescription ?? "Unknown error")"
        content.categoryIdentifier = "UPLOAD_FAILED"

        if playSound {
            content.sound = UNNotificationSound.defaultCritical
        }

        content.userInfo = [
            "jobId": job.id.uuidString
        ]

        await send(content: content, identifier: "failed-\(job.id)")
    }

    /// Notifies that all uploads are complete
    public func notifyAllUploadsComplete(count: Int, failed: Int) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()

        if failed == 0 {
            content.title = "All Uploads Complete"
            content.body = "\(count) file\(count == 1 ? "" : "s") uploaded successfully"
        } else {
            content.title = "Uploads Finished"
            content.body = "\(count - failed) completed, \(failed) failed"
        }

        content.categoryIdentifier = "UPLOADS_COMPLETE"

        if playSound {
            content.sound = .default
        }

        await send(content: content, identifier: "all-complete-\(Date().timeIntervalSince1970)")
    }

    /// Notifies about session expiration
    public func notifySessionExpiring(in minutes: Int) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "AWS Session Expiring"
        content.body = "Your session will expire in \(minutes) minutes. Re-authenticate to continue uploads."
        content.categoryIdentifier = "SESSION_WARNING"

        if playSound {
            content.sound = .default
        }

        await send(content: content, identifier: "session-expiring")
    }

    /// Notifies about skill execution results
    public func notifySkillResults(filename: String, successCount: Int, failedSkills: [String]) async {
        guard isEnabled else { return }
        guard !failedSkills.isEmpty else { return }  // Only notify on failures

        let content = UNMutableNotificationContent()
        content.title = "Skills Warning"

        if failedSkills.count == 1 {
            content.body = "\(failedSkills[0]) failed for \(filename)"
        } else {
            content.body = "\(failedSkills.count) skills failed for \(filename)"
        }

        content.categoryIdentifier = "SKILL_WARNING"

        if playSound {
            content.sound = .default
        }

        await send(content: content, identifier: "skill-warning-\(Date().timeIntervalSince1970)")
    }

    // MARK: - Helpers

    private func send(content: UNMutableNotificationContent, identifier: String) async {
        guard isAvailable else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.debug("Sent notification: \(identifier)")
        } catch {
            logger.error("Failed to send notification: \(error)")
        }
    }

    /// Removes pending notifications for a job
    public func removeNotifications(for jobId: UUID) {
        guard isAvailable else { return }

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "start-\(jobId)",
                "complete-\(jobId)",
                "failed-\(jobId)"
            ]
        )
    }

    /// Sets up notification categories and actions
    public func setupCategories() {
        guard isAvailable else {
            logger.info("Skipping notification setup - not running in app bundle")
            return
        }
        let copyAction = UNNotificationAction(
            identifier: "COPY_URL",
            title: "Copy S3 URL",
            options: []
        )

        let openAction = UNNotificationAction(
            identifier: "OPEN_CONSOLE",
            title: "Open in Console",
            options: [.foreground]
        )

        let retryAction = UNNotificationAction(
            identifier: "RETRY",
            title: "Retry",
            options: []
        )

        let completeCategory = UNNotificationCategory(
            identifier: "UPLOAD_COMPLETE",
            actions: [copyAction, openAction],
            intentIdentifiers: [],
            options: []
        )

        let failedCategory = UNNotificationCategory(
            identifier: "UPLOAD_FAILED",
            actions: [retryAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            completeCategory,
            failedCategory
        ])
    }
}
