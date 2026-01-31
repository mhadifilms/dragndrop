import Foundation

// MARK: - Upload Schedule

/// Configuration for when uploads should be allowed to run
public struct UploadSchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var mode: ScheduleMode
    public var rules: [ScheduleRule]
    public var queuedUploads: [ScheduledUpload]

    public init(
        isEnabled: Bool = false,
        mode: ScheduleMode = .allowDuring,
        rules: [ScheduleRule] = [],
        queuedUploads: [ScheduledUpload] = []
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.rules = rules
        self.queuedUploads = queuedUploads
    }

    /// Check if uploads are currently allowed based on the schedule
    public func isUploadAllowed(at date: Date = Date()) -> Bool {
        guard isEnabled else { return true }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        // Find matching rules for today
        let activeRules = rules.filter { rule in
            rule.isEnabled && rule.daysOfWeek.contains(weekday)
        }

        if activeRules.isEmpty {
            // No rules for today - use default behavior
            return mode == .allowDuring ? false : true
        }

        // Check if current time falls within any rule
        let isWithinRule = activeRules.contains { rule in
            rule.isTimeWithin(currentMinutes)
        }

        return mode == .allowDuring ? isWithinRule : !isWithinRule
    }

    /// Get the next time uploads will be allowed
    public func nextAllowedTime(from date: Date = Date()) -> Date? {
        guard isEnabled, !isUploadAllowed(at: date) else { return nil }

        let calendar = Calendar.current

        // Search up to 7 days ahead
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: checkDate)
            let rulesForDay = rules.filter { $0.isEnabled && $0.daysOfWeek.contains(weekday) }

            for rule in rulesForDay {
                let startHour = rule.startTimeMinutes / 60
                let startMinute = rule.startTimeMinutes % 60

                var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
                components.hour = startHour
                components.minute = startMinute
                components.second = 0

                if let ruleStart = calendar.date(from: components) {
                    if ruleStart > date {
                        return mode == .allowDuring ? ruleStart : nil
                    }
                }
            }
        }

        return nil
    }

    /// Pre-defined schedule templates
    public static let offHoursOnly = UploadSchedule(
        isEnabled: true,
        mode: .allowDuring,
        rules: [
            ScheduleRule(
                name: "Evenings & Nights (Weekdays)",
                startTimeMinutes: 18 * 60,  // 6 PM
                endTimeMinutes: 9 * 60,     // 9 AM (overnight)
                daysOfWeek: Set(2...6)      // Mon-Fri
            ),
            ScheduleRule(
                name: "All Day Weekend",
                startTimeMinutes: 0,
                endTimeMinutes: 1440,
                daysOfWeek: Set([1, 7])     // Sun, Sat
            )
        ]
    )

    public static let businessHoursOnly = UploadSchedule(
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
}

// MARK: - Schedule Mode

public enum ScheduleMode: String, Codable, CaseIterable, Sendable {
    case allowDuring = "Allow uploads during these times"
    case blockDuring = "Block uploads during these times"

    public var description: String { rawValue }
}

// MARK: - Schedule Rule

public struct ScheduleRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var startTimeMinutes: Int  // Minutes from midnight
    public var endTimeMinutes: Int    // Minutes from midnight
    public var daysOfWeek: Set<Int>   // 1 = Sunday, 7 = Saturday

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        startTimeMinutes: Int,
        endTimeMinutes: Int,
        daysOfWeek: Set<Int>
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.startTimeMinutes = startTimeMinutes
        self.endTimeMinutes = endTimeMinutes
        self.daysOfWeek = daysOfWeek
    }

    /// Check if a time (in minutes from midnight) is within this rule
    public func isTimeWithin(_ minutes: Int) -> Bool {
        if startTimeMinutes <= endTimeMinutes {
            // Same day range (e.g., 9 AM to 5 PM)
            return minutes >= startTimeMinutes && minutes < endTimeMinutes
        } else {
            // Overnight range (e.g., 6 PM to 9 AM)
            return minutes >= startTimeMinutes || minutes < endTimeMinutes
        }
    }

    // Formatted times
    public var startTimeString: String {
        let hours = startTimeMinutes / 60
        let mins = startTimeMinutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    public var endTimeString: String {
        let hours = endTimeMinutes / 60
        let mins = endTimeMinutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    public var daysDescription: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sortedDays = daysOfWeek.sorted()

        // Check for common patterns
        if sortedDays == Array(2...6) { return "Weekdays" }
        if sortedDays == [1, 7] { return "Weekends" }
        if sortedDays == Array(1...7) { return "Every day" }

        return sortedDays.map { dayNames[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - Scheduled Upload

/// Represents an upload that's been queued for later
public struct ScheduledUpload: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var fileURL: URL
    public var workflowId: UUID
    public var scheduledFor: Date?  // nil = run when schedule allows
    public var addedAt: Date
    public var priority: Int  // Higher = more important

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        workflowId: UUID,
        scheduledFor: Date? = nil,
        addedAt: Date = Date(),
        priority: Int = 0
    ) {
        self.id = id
        self.fileURL = fileURL
        self.workflowId = workflowId
        self.scheduledFor = scheduledFor
        self.addedAt = addedAt
        self.priority = priority
    }
}

// MARK: - Upload Scheduler Service

/// Manages scheduled uploads and determines when they can run
public actor UploadScheduler {
    private var schedule: UploadSchedule
    private var queuedUploads: [ScheduledUpload] = []
    private var isRunning = false
    private var checkTask: Task<Void, Never>?
    private var statusCallback: ((SchedulerStatus) -> Void)?

    public init(schedule: UploadSchedule = UploadSchedule()) {
        self.schedule = schedule
        self.queuedUploads = schedule.queuedUploads
    }

    // MARK: - Configuration

    public func updateSchedule(_ newSchedule: UploadSchedule) {
        self.schedule = newSchedule
        notifyStatusChange()
    }

    public func setStatusCallback(_ callback: @escaping (SchedulerStatus) -> Void) {
        self.statusCallback = callback
        notifyStatusChange()
    }

    // MARK: - Queue Management

    /// Add files to the upload queue
    public func queueUpload(_ upload: ScheduledUpload) {
        queuedUploads.append(upload)
        queuedUploads.sort { $0.priority > $1.priority }
        notifyStatusChange()
    }

    /// Add multiple files to the queue
    public func queueUploads(_ uploads: [ScheduledUpload]) {
        queuedUploads.append(contentsOf: uploads)
        queuedUploads.sort { $0.priority > $1.priority }
        notifyStatusChange()
    }

    /// Remove an upload from the queue
    public func dequeueUpload(id: UUID) {
        queuedUploads.removeAll { $0.id == id }
        notifyStatusChange()
    }

    /// Get all queued uploads
    public func getQueuedUploads() -> [ScheduledUpload] {
        return queuedUploads
    }

    /// Clear the queue
    public func clearQueue() {
        queuedUploads.removeAll()
        notifyStatusChange()
    }

    // MARK: - Scheduling Logic

    /// Check if uploads can proceed now
    public func canUploadNow() -> Bool {
        return schedule.isUploadAllowed()
    }

    /// Get uploads that are ready to run
    public func getReadyUploads() -> [ScheduledUpload] {
        guard canUploadNow() else { return [] }

        let now = Date()
        return queuedUploads.filter { upload in
            if let scheduledFor = upload.scheduledFor {
                return scheduledFor <= now
            }
            return true  // No specific time = ready when schedule allows
        }
    }

    /// Mark uploads as started (remove from queue)
    public func markUploadsStarted(_ ids: [UUID]) {
        queuedUploads.removeAll { ids.contains($0.id) }
        notifyStatusChange()
    }

    // MARK: - Scheduler Control

    /// Start the scheduler
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkSchedule()
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // Check every minute
            }
        }

        notifyStatusChange()
    }

    /// Stop the scheduler
    public func stop() {
        isRunning = false
        checkTask?.cancel()
        checkTask = nil
        notifyStatusChange()
    }

    private func checkSchedule() {
        // This would trigger upload starts when the schedule window opens
        notifyStatusChange()
    }

    // MARK: - Status

    public func getStatus() -> SchedulerStatus {
        return SchedulerStatus(
            isEnabled: schedule.isEnabled,
            isRunning: isRunning,
            canUploadNow: canUploadNow(),
            queuedCount: queuedUploads.count,
            nextAllowedTime: schedule.nextAllowedTime(),
            currentMode: schedule.mode
        )
    }

    private func notifyStatusChange() {
        let status = SchedulerStatus(
            isEnabled: schedule.isEnabled,
            isRunning: isRunning,
            canUploadNow: canUploadNow(),
            queuedCount: queuedUploads.count,
            nextAllowedTime: schedule.nextAllowedTime(),
            currentMode: schedule.mode
        )
        statusCallback?(status)
    }
}

// MARK: - Scheduler Status

public struct SchedulerStatus: Sendable {
    public let isEnabled: Bool
    public let isRunning: Bool
    public let canUploadNow: Bool
    public let queuedCount: Int
    public let nextAllowedTime: Date?
    public let currentMode: ScheduleMode

    public var statusText: String {
        if !isEnabled {
            return "Scheduling disabled"
        }

        if canUploadNow {
            return queuedCount > 0 ? "\(queuedCount) uploads ready" : "Ready to upload"
        }

        if let nextTime = nextAllowedTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Uploads resume \(formatter.localizedString(for: nextTime, relativeTo: Date()))"
        }

        return "Outside upload window"
    }
}

// MARK: - Schedule Presets

public enum SchedulePreset: String, CaseIterable, Sendable {
    case none = "No Schedule"
    case offHours = "Off-Hours Only"
    case businessHours = "Business Hours Only"
    case weekendsOnly = "Weekends Only"
    case nightsOnly = "Nights Only"
    case custom = "Custom"

    public var schedule: UploadSchedule? {
        switch self {
        case .none:
            return UploadSchedule(isEnabled: false)
        case .offHours:
            return .offHoursOnly
        case .businessHours:
            return .businessHoursOnly
        case .weekendsOnly:
            return UploadSchedule(
                isEnabled: true,
                mode: .allowDuring,
                rules: [
                    ScheduleRule(
                        name: "All Day Weekend",
                        startTimeMinutes: 0,
                        endTimeMinutes: 1440,
                        daysOfWeek: Set([1, 7])
                    )
                ]
            )
        case .nightsOnly:
            return UploadSchedule(
                isEnabled: true,
                mode: .allowDuring,
                rules: [
                    ScheduleRule(
                        name: "Night Hours",
                        startTimeMinutes: 22 * 60,  // 10 PM
                        endTimeMinutes: 6 * 60,     // 6 AM
                        daysOfWeek: Set(1...7)
                    )
                ]
            )
        case .custom:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .none: return "Uploads run immediately"
        case .offHours: return "After 6 PM and weekends"
        case .businessHours: return "9 AM - 5 PM on weekdays"
        case .weekendsOnly: return "Saturday and Sunday only"
        case .nightsOnly: return "10 PM - 6 AM every day"
        case .custom: return "Configure your own schedule"
        }
    }
}
