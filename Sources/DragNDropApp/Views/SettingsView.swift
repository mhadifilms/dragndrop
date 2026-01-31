import SwiftUI
import DragNDropCore

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AWSSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("AWS", systemImage: "cloud")
                }

            UploadSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Uploads", systemImage: "arrow.up.circle")
                }

            ScheduleSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Schedule", systemImage: "clock")
                }

            FileFilterSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }

            AdvancedSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)

                Picker("Appearance", selection: $appState.settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Label(theme.rawValue, systemImage: theme.iconName).tag(theme)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Show notifications", isOn: $appState.settings.showNotifications)

                Toggle("Play sound", isOn: $appState.settings.notificationSound)
                    .disabled(!appState.settings.showNotifications)
            }

            Section("Behavior") {
                Toggle("Auto-start uploads when files dropped", isOn: $appState.settings.autoStartUploads)

                Toggle("Confirm before uploading", isOn: $appState.settings.confirmBeforeUpload)
                    .disabled(appState.settings.autoStartUploads)

                Toggle("Close window after starting upload", isOn: $appState.settings.closeWindowAfterUploadStart)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            appState.settings.save()
        }
    }
}

// MARK: - AWS Settings

struct AWSSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var sessionToken: String = ""
    @State private var region: String = "us-east-1"
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showingRegionSelector = false

    enum TestResult {
        case success(String)
        case failure(String)
    }

    /// Detect if using temporary credentials (ASIA prefix = STS/SSO)
    private var isTemporaryCredentials: Bool {
        accessKey.hasPrefix("ASIA")
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: appState.isAuthenticated ? "checkmark.circle.fill" : "key.fill")
                        .font(.title2)
                        .foregroundStyle(appState.isAuthenticated ? .green : .secondary)

                    VStack(alignment: .leading) {
                        Text(appState.isAuthenticated ? "Connected" : "Not Connected")
                            .font(.headline)

                        if appState.isAuthenticated {
                            Text("Credentials configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Add your AWS credentials below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if appState.isAuthenticated {
                        Button("Clear Credentials") {
                            clearCredentials()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            if let result = testResult {
                Section {
                    HStack {
                        switch result {
                        case .success(let message):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("AWS Credentials") {
                TextField("Access Key ID", text: $accessKey)
                    .textContentType(.username)
                    .font(.system(.body, design: .monospaced))

                SecureField("Secret Access Key", text: $secretKey)
                    .textContentType(.password)
                    .font(.system(.body, design: .monospaced))

                // Show session token field for temporary credentials (ASIA*)
                if isTemporaryCredentials || !sessionToken.isEmpty {
                    SecureField("Session Token", text: $sessionToken)
                        .textContentType(.password)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Region")
                    Spacer()
                    if let awsRegion = AWSRegion.region(for: region) {
                        HStack(spacing: 6) {
                            Text(awsRegion.flag)
                            Text(awsRegion.name)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    Button {
                        showingRegionSelector = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                            Text("Testing...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accessKey.isEmpty || secretKey.isEmpty || isTesting || (isTemporaryCredentials && sessionToken.isEmpty))
                }
            }

            Section {
                if isTemporaryCredentials {
                    Label("Temporary credentials detected (ASIA*). Session token required.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Get credentials from AWS Console → IAM → Users → Security credentials, or copy temporary credentials from AWS SSO portal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCredentials()
        }
        .onDisappear {
            appState.settings.save()
        }
        .sheet(isPresented: $showingRegionSelector) {
            RegionPickerSheet(selectedRegionId: $region)
        }
    }

    private func loadCredentials() {
        // Load from appState if available
        if let creds = appState.authState.credentials {
            accessKey = creds.accessKeyId
            // Don't load secret key for security - user must re-enter
        }
        region = appState.settings.awsRegion
    }

    private func clearCredentials() {
        accessKey = ""
        secretKey = ""
        sessionToken = ""
        testResult = nil
        Task { await appState.signOut() }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        do {
            try await appState.setCredentials(
                accessKey: accessKey,
                secretKey: secretKey,
                sessionToken: sessionToken.isEmpty ? nil : sessionToken,
                region: region
            )
            testResult = .success("Connection successful!")
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }
}

// MARK: - Upload Settings

struct UploadSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Parallel Uploads") {
                Stepper(
                    "Concurrent uploads: \(appState.settings.defaultUploadSettings.maxConcurrentUploads)",
                    value: $appState.settings.defaultUploadSettings.maxConcurrentUploads,
                    in: 1...16
                )

                Text("More concurrent uploads = faster total time, but more bandwidth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Multipart Upload") {
                Stepper(
                    "Threshold: \(appState.settings.defaultUploadSettings.multipartThresholdMB) MB",
                    value: $appState.settings.defaultUploadSettings.multipartThresholdMB,
                    in: 5...100,
                    step: 5
                )

                Stepper(
                    "Part size: \(appState.settings.defaultUploadSettings.partSizeMB) MB",
                    value: $appState.settings.defaultUploadSettings.partSizeMB,
                    in: 5...100,
                    step: 5
                )

                Toggle("Enable resumable uploads", isOn: $appState.settings.defaultUploadSettings.enableResumable)
            }

            Section("Reliability & Retry") {
                Stepper(
                    "Max retry attempts: \(appState.settings.defaultUploadSettings.retryCount)",
                    value: $appState.settings.defaultUploadSettings.retryCount,
                    in: 0...10
                )

                Stepper(
                    "Base retry delay: \(appState.settings.defaultUploadSettings.retryDelaySeconds)s",
                    value: $appState.settings.defaultUploadSettings.retryDelaySeconds,
                    in: 1...60
                )

                Text("Uses exponential backoff: 5s → 10s → 20s → 40s...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Verify checksum after upload", isOn: $appState.settings.defaultUploadSettings.verifyChecksum)
            }

            Section("Bandwidth Throttling") {
                Toggle("Enable bandwidth limit", isOn: $appState.settings.defaultUploadSettings.enableBandwidthThrottling)

                if appState.settings.defaultUploadSettings.enableBandwidthThrottling {
                    HStack {
                        Text("Max upload speed:")
                        Spacer()
                        TextField(
                            "Speed",
                            value: $appState.settings.defaultUploadSettings.maxUploadSpeedMBps,
                            format: .number.precision(.fractionLength(1))
                        )
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        Text("MB/s")
                            .foregroundStyle(.secondary)
                    }

                    // Quick presets
                    HStack {
                        Text("Presets:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ForEach([1.0, 5.0, 10.0, 25.0, 50.0], id: \.self) { speed in
                            Button("\(Int(speed))") {
                                appState.settings.defaultUploadSettings.maxUploadSpeedMBps = speed
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                        Button("∞") {
                            appState.settings.defaultUploadSettings.enableBandwidthThrottling = false
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    Text("Limit upload speed to avoid saturating your network connection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                Picker("Storage class", selection: $appState.settings.defaultUploadSettings.storageClass) {
                    ForEach(S3StorageClass.allCases, id: \.self) { storageClass in
                        Text(storageClass.displayName).tag(storageClass)
                    }
                }

                Toggle("Server-side encryption", isOn: $appState.settings.defaultUploadSettings.enableEncryption)

                if appState.settings.defaultUploadSettings.enableEncryption {
                    Picker("Encryption type", selection: $appState.settings.defaultUploadSettings.encryptionType) {
                        ForEach(S3EncryptionType.allCases.filter { $0 != .none }, id: \.self) { encType in
                            Text(encType.displayName).tag(encType)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            appState.settings.save()
        }
    }
}

// MARK: - File Filter Settings

struct FileFilterSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newExtension = ""
    @State private var selectedPreset: FileExtensionPreset = .vfxAll

    var body: some View {
        Form {
            Section {
                Toggle("Enable file type filtering", isOn: $appState.settings.enableFileTypeFilter)

                Text("When enabled, only files matching your criteria will be accepted for upload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.settings.enableFileTypeFilter {
                Section("Quick Presets") {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(FileExtensionPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: selectedPreset) { _, preset in
                        if preset != .custom {
                            appState.settings.allowedFileExtensions = preset.extensions
                        }
                    }

                    Text(selectedPreset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Allowed Extensions") {
                    ExtensionListEditor(
                        extensions: $appState.settings.allowedFileExtensions,
                        title: "Allowed",
                        color: .green
                    )
                }

                Section("Blocked Extensions") {
                    ExtensionListEditor(
                        extensions: $appState.settings.blockedFileExtensions,
                        title: "Blocked",
                        color: .red
                    )

                    Text("Blocked extensions take priority over allowed extensions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Size Limit") {
                    HStack {
                        Text("Maximum file size:")
                        Spacer()
                        if appState.settings.maxFileSizeMB == 0 {
                            Text("Unlimited")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(appState.settings.maxFileSizeMB) MB")
                        }
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appState.settings.maxFileSizeMB) },
                            set: { appState.settings.maxFileSizeMB = Int($0) }
                        ),
                        in: 0...10000,
                        step: 100
                    )

                    Text("Set to 0 for unlimited file size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Other") {
                    Toggle("Allow hidden files (starting with .)", isOn: $appState.settings.allowHiddenFiles)
                }
            }

            Section("Duplicate Detection") {
                Toggle("Enable duplicate detection", isOn: $appState.settings.enableDuplicateDetection)

                if appState.settings.enableDuplicateDetection {
                    Toggle("Check S3 for existing files", isOn: $appState.settings.checkS3ForDuplicates)

                    Picker("When duplicate found", selection: $appState.settings.duplicateAction) {
                        ForEach(DuplicateDetectionService.DuplicateAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }

                    Text(appState.settings.duplicateAction.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            appState.settings.save()
        }
    }
}

// MARK: - Extension List Editor

struct ExtensionListEditor: View {
    @Binding var extensions: [String]
    let title: String
    let color: Color

    @State private var newExtension = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display current extensions as chips
            FlowLayoutView(alignment: .leading, spacing: 4) {
                ForEach(extensions.sorted(), id: \.self) { ext in
                    HStack(spacing: 4) {
                        Text(".\(ext)")
                            .font(.caption)

                        Button {
                            extensions.removeAll { $0 == ext }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                }
            }

            // Add new extension
            HStack {
                TextField("Add extension", text: $newExtension)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit {
                        addExtension()
                    }

                Button("Add") {
                    addExtension()
                }
                .disabled(newExtension.isEmpty)
            }
        }
    }

    private func addExtension() {
        let ext = newExtension
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")

        guard !ext.isEmpty, !extensions.contains(ext) else {
            newExtension = ""
            return
        }

        extensions.append(ext)
        newExtension = ""
    }
}

// MARK: - Flow Layout for Extension Chips

struct FlowLayoutView<Content: View>: View {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        _FlowLayout(alignment: alignment, spacing: spacing) {
            content()
        }
    }
}

private struct _FlowLayout: Layout {
    let alignment: HorizontalAlignment
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxProposedWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxProposedWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Schedule Settings

struct ScheduleSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPreset: SchedulePreset = .none
    @State private var showingRuleEditor = false
    @State private var editingRule: ScheduleRule?

    var body: some View {
        Form {
            Section {
                Toggle("Enable upload scheduling", isOn: $appState.settings.uploadSchedule.isEnabled)

                Text("Schedule uploads to run during specific time windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.settings.uploadSchedule.isEnabled {
                Section("Quick Presets") {
                    Picker("Schedule", selection: $selectedPreset) {
                        ForEach(SchedulePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .onChange(of: selectedPreset) { _, preset in
                        if let schedule = preset.schedule {
                            appState.settings.uploadSchedule = schedule
                            appState.settings.selectedSchedulePreset = preset.rawValue
                        }
                    }

                    Text(selectedPreset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Mode") {
                    Picker("When to upload", selection: $appState.settings.uploadSchedule.mode) {
                        ForEach(ScheduleMode.allCases, id: \.self) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Time Windows") {
                    if appState.settings.uploadSchedule.rules.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No time windows configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                    } else {
                        ForEach(appState.settings.uploadSchedule.rules) { rule in
                            ScheduleRuleRow(rule: rule, onEdit: {
                                editingRule = rule
                                showingRuleEditor = true
                            }, onDelete: {
                                deleteRule(rule)
                            }, onToggle: {
                                toggleRule(rule)
                            })
                        }
                    }

                    Button {
                        editingRule = nil
                        showingRuleEditor = true
                    } label: {
                        Label("Add Time Window", systemImage: "plus.circle")
                    }
                }

                Section("Current Status") {
                    let isAllowed = appState.settings.uploadSchedule.isUploadAllowed()

                    HStack {
                        Image(systemName: isAllowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isAllowed ? .green : .red)

                        VStack(alignment: .leading) {
                            Text(isAllowed ? "Uploads are allowed now" : "Uploads are blocked")
                                .font(.subheadline)

                            if !isAllowed, let nextTime = appState.settings.uploadSchedule.nextAllowedTime() {
                                Text("Next window: \(nextTime, style: .relative)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Set selected preset based on saved value
            if let preset = SchedulePreset(rawValue: appState.settings.selectedSchedulePreset) {
                selectedPreset = preset
            }
        }
        .onDisappear {
            appState.settings.save()
        }
        .sheet(isPresented: $showingRuleEditor) {
            ScheduleRuleEditor(rule: editingRule, onSave: { rule in
                saveRule(rule)
            })
        }
    }

    private func deleteRule(_ rule: ScheduleRule) {
        appState.settings.uploadSchedule.rules.removeAll { $0.id == rule.id }
        selectedPreset = .custom
    }

    private func toggleRule(_ rule: ScheduleRule) {
        if let index = appState.settings.uploadSchedule.rules.firstIndex(where: { $0.id == rule.id }) {
            appState.settings.uploadSchedule.rules[index].isEnabled.toggle()
        }
    }

    private func saveRule(_ rule: ScheduleRule) {
        if let index = appState.settings.uploadSchedule.rules.firstIndex(where: { $0.id == rule.id }) {
            appState.settings.uploadSchedule.rules[index] = rule
        } else {
            appState.settings.uploadSchedule.rules.append(rule)
        }
        selectedPreset = .custom
    }
}

// MARK: - Schedule Rule Row

struct ScheduleRuleRow: View {
    let rule: ScheduleRule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: .constant(rule.isEnabled))
                .labelsHidden()
                .onTapGesture { onToggle() }

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.subheadline)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    Label(rule.daysDescription, systemImage: "calendar")
                    Label("\(rule.startTimeString) - \(rule.endTimeString)", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Schedule Rule Editor

struct ScheduleRuleEditor: View {
    let rule: ScheduleRule?
    let onSave: (ScheduleRule) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var startHour: Int = 18
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 9
    @State private var endMinute: Int = 0
    @State private var selectedDays: Set<Int> = Set(2...6)

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule == nil ? "Add Time Window" : "Edit Time Window")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                Section("Name") {
                    TextField("e.g., Evening Hours", text: $name)
                }

                Section("Start Time") {
                    HStack {
                        Picker("Hour", selection: $startHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)

                        Text(":")

                        Picker("Minute", selection: $startMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .frame(width: 80)
                    }
                }

                Section("End Time") {
                    HStack {
                        Picker("Hour", selection: $endHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)

                        Text(":")

                        Picker("Minute", selection: $endMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .frame(width: 80)
                    }

                    if startHour * 60 + startMinute > endHour * 60 + endMinute {
                        Text("Overnight window: ends the next day")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Days of Week") {
                    HStack(spacing: 8) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            } label: {
                                Text(dayNames[day - 1])
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(selectedDays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.2))
                                    .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Weekdays") {
                            selectedDays = Set(2...6)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Weekends") {
                            selectedDays = Set([1, 7])
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Every Day") {
                            selectedDays = Set(1...7)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || selectedDays.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            if let rule = rule {
                name = rule.name
                startHour = rule.startTimeMinutes / 60
                startMinute = rule.startTimeMinutes % 60
                endHour = rule.endTimeMinutes / 60
                endMinute = rule.endTimeMinutes % 60
                selectedDays = rule.daysOfWeek
            }
        }
    }

    private func save() {
        let newRule = ScheduleRule(
            id: rule?.id ?? UUID(),
            name: name,
            isEnabled: rule?.isEnabled ?? true,
            startTimeMinutes: startHour * 60 + startMinute,
            endTimeMinutes: endHour * 60 + endMinute,
            daysOfWeek: selectedDays
        )
        onSave(newRule)
        dismiss()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("CLI Server") {
                Toggle("Enable CLI control", isOn: $appState.settings.enableCLIServer)

                if appState.settings.enableCLIServer {
                    HStack {
                        Text("Port:")
                        TextField("Port", value: $appState.settings.cliServerPort, format: .number)
                            .frame(width: 80)
                    }

                    Text("Connect with: shotdrop --port \(appState.settings.cliServerPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History") {
                Stepper(
                    "Keep history for \(appState.settings.keepHistoryDays) days",
                    value: $appState.settings.keepHistoryDays,
                    in: 1...365
                )

                Stepper(
                    "Max history items: \(appState.settings.maxHistoryItems)",
                    value: $appState.settings.maxHistoryItems,
                    in: 100...10000,
                    step: 100
                )

                Button("Clear History") {
                    // Clear history
                }
                .foregroundStyle(.red)
            }

            Section("Debug") {
                Toggle("Enable debug logging", isOn: $appState.settings.enableDebugLogging)

                Button("Open Log File") {
                    openLogFile()
                }

                Button("Export Diagnostics") {
                    exportDiagnostics()
                }
            }

            Section("Finder Integration") {
                Button("Install Finder Quick Action") {
                    installFinderQuickAction()
                }

                Button("Copy Shell Script") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(FinderIntegration.shellScriptForUpload, forType: .string)
                }

                Text("URL Scheme: dragndrop://upload?file=/path/to/file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Reset") {
                Button("Reset All Settings") {
                    AppSettings.reset()
                    appState.settings = AppSettings()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            appState.settings.save()
        }
    }

    private func openLogFile() {
        let logPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("dragndrop/logs")
        NSWorkspace.shared.open(logPath)
    }

    private func exportDiagnostics() {
        // Export diagnostics
    }

    private func installFinderQuickAction() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Upload with dragndrop.workflow"
        panel.allowedContentTypes = [.init(filenameExtension: "workflow")!]
        panel.directoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Services")

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try FinderIntegration.shared.exportAutomatorWorkflow(to: url)
                } catch {
                    print("Failed to export workflow: \(error)")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
