import SwiftUI
import DragNDropCore

// MARK: - Dashboard View

/// A comprehensive dashboard showing upload statistics and performance metrics
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTimeRange: TimeRange = .today
    @State private var hasAppeared = false

    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with time range picker
                headerSection

                // Quick stats
                statsGrid

                // Upload activity chart
                uploadActivityChart

                // Storage usage
                storageUsageSection

                // Recent activity
                recentActivitySection
            }
            .padding()
        }
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Overview of your upload activity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Total Uploads",
                value: "1,247",
                icon: "arrow.up.circle.fill",
                color: .blue,
                trend: .up(12)
            )

            StatCard(
                title: "Data Transferred",
                value: "2.4 TB",
                icon: "externaldrive.fill",
                color: .purple,
                trend: .up(8)
            )

            StatCard(
                title: "Avg Speed",
                value: "45 MB/s",
                icon: "speedometer",
                color: .green,
                trend: .neutral
            )

            StatCard(
                title: "Success Rate",
                value: "99.2%",
                icon: "checkmark.circle.fill",
                color: .green,
                trend: .up(2)
            )
        }
    }

    // MARK: - Upload Activity Chart

    private var uploadActivityChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Upload Activity")
                    .font(.headline)

                Spacer()

                HStack(spacing: 16) {
                    LegendItem(color: .blue, label: "Uploads")
                    LegendItem(color: .green, label: "Success")
                    LegendItem(color: .red, label: "Failed")
                }
            }

            // Chart
            UploadActivityChart(data: sampleChartData)
                .frame(height: 200)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Storage Usage Section

    private var storageUsageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage by Category")
                    .font(.headline)

                Spacer()

                Text("2.4 TB total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Category breakdown
            VStack(spacing: 12) {
                StorageCategoryBar(category: "Nuke Projects", used: 850, total: 2400, color: .purple)
                StorageCategoryBar(category: "Image Sequences", used: 720, total: 2400, color: .blue)
                StorageCategoryBar(category: "Videos", used: 450, total: 2400, color: .pink)
                StorageCategoryBar(category: "Other", used: 380, total: 2400, color: .gray)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)

                Spacer()

                Button("View All") {
                    // Navigate to history
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                ActivityRow(
                    action: "Uploaded",
                    filename: "SHOW_101_0010_comp_v005.nk",
                    time: "2 minutes ago",
                    status: .success
                )
                ActivityRow(
                    action: "Uploaded",
                    filename: "SHOW_101_0020_render_v003.exr",
                    time: "5 minutes ago",
                    status: .success
                )
                ActivityRow(
                    action: "Failed",
                    filename: "SHOW_101_0030_plate.mov",
                    time: "12 minutes ago",
                    status: .failed
                )
                ActivityRow(
                    action: "Uploaded",
                    filename: "SHOW_102_0010_comp_v001.nk",
                    time: "1 hour ago",
                    status: .success
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Sample chart data
    private var sampleChartData: [ChartDataPoint] {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return days.enumerated().map { index, day in
            ChartDataPoint(
                label: day,
                value: Double.random(in: 20...100),
                secondaryValue: Double.random(in: 15...95)
            )
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: Trend

    @State private var hasAppeared = false
    @State private var isHovered = false

    enum Trend {
        case up(Int)
        case down(Int)
        case neutral

        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }

        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .secondary
            }
        }

        var text: String {
            switch self {
            case .up(let value): return "+\(value)%"
            case .down(let value): return "-\(value)%"
            case .neutral: return "0%"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                }

                Spacer()

                // Trend indicator
                HStack(spacing: 2) {
                    Image(systemName: trend.icon)
                        .font(.caption2)
                    Text(trend.text)
                        .font(.caption2)
                }
                .foregroundStyle(trend.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(trend.color.opacity(0.1))
                .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.05))
        )
        .scaleEffect(hasAppeared ? 1.0 : 0.9)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(Double.random(in: 0...0.2))) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Upload Activity Chart

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    var secondaryValue: Double? = nil
}

struct UploadActivityChart: View {
    let data: [ChartDataPoint]

    @State private var hasAppeared = false

    var maxValue: Double {
        data.map { max($0.value, $0.secondaryValue ?? 0) }.max() ?? 100
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, point in
                    VStack(spacing: 4) {
                        // Bars
                        ZStack(alignment: .bottom) {
                            // Primary bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.8), .blue.opacity(0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: hasAppeared ? barHeight(for: point.value, in: geometry) : 0)

                            // Secondary bar (overlay)
                            if let secondary = point.secondaryValue {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green.opacity(0.6))
                                    .frame(width: 8, height: hasAppeared ? barHeight(for: secondary, in: geometry) : 0)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .animation(AnimationPresets.spring.delay(Double(index) * 0.05), value: hasAppeared)

                        // Label
                        Text(point.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
        }
    }

    private func barHeight(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        let availableHeight = geometry.size.height - 30
        return CGFloat(value / maxValue) * availableHeight
    }
}

// MARK: - Storage Category Bar

struct StorageCategoryBar: View {
    let category: String
    let used: Double  // GB
    let total: Double  // GB
    let color: Color

    @State private var hasAppeared = false

    var percentage: Double {
        used / total
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(category)
                    .font(.subheadline)

                Spacer()

                Text("\(Int(used)) GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: hasAppeared ? geometry.size.width * percentage : 0)
                        .animation(AnimationPresets.spring, value: hasAppeared)
                }
            }
            .frame(height: 8)
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let action: String
    let filename: String
    let time: String
    let status: ActivityStatus

    @State private var isHovered = false

    enum ActivityStatus {
        case success
        case failed
        case pending

        var color: Color {
            switch self {
            case .success: return .green
            case .failed: return .red
            case .pending: return .orange
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .pending: return "clock.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .frame(width: 20)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.subheadline)
                    .lineLimit(1)

                Text("\(action) · \(time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Speed Graph Widget

struct SpeedGraphWidget: View {
    @State private var speedHistory: [Double] = []
    @State private var currentSpeed: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upload Speed")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                    Text(String(format: "%.1f MB/s", currentSpeed))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .foregroundStyle(Color.accentColor)
            }

            // Mini speed graph
            SpeedLineGraph(data: speedHistory)
                .frame(height: 60)

            // Stats
            HStack {
                VStack(alignment: .leading) {
                    Text("Peak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f MB/s", speedHistory.max() ?? 0))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .center) {
                    Text("Average")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f MB/s", averageSpeed))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f MB/s", currentSpeed))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            startSimulation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var averageSpeed: Double {
        guard !speedHistory.isEmpty else { return 0 }
        return speedHistory.reduce(0, +) / Double(speedHistory.count)
    }

    private func startSimulation() {
        // Simulate speed updates for demo
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentSpeed = Double.random(in: 30...60)
            speedHistory.append(currentSpeed)
            if speedHistory.count > 30 {
                speedHistory.removeFirst()
            }
        }
    }
}

// MARK: - Speed Line Graph

struct SpeedLineGraph: View {
    let data: [Double]

    var maxValue: Double {
        data.max() ?? 100
    }

    var body: some View {
        GeometryReader { geometry in
            if data.count > 1 {
                Path { path in
                    let stepX = geometry.size.width / CGFloat(max(data.count - 1, 1))
                    let stepY = geometry.size.height / CGFloat(maxValue)

                    path.move(to: CGPoint(
                        x: 0,
                        y: geometry.size.height - CGFloat(data[0]) * stepY
                    ))

                    for (index, value) in data.enumerated().dropFirst() {
                        path.addLine(to: CGPoint(
                            x: CGFloat(index) * stepX,
                            y: geometry.size.height - CGFloat(value) * stepY
                        ))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // Area fill
                Path { path in
                    let stepX = geometry.size.width / CGFloat(max(data.count - 1, 1))
                    let stepY = geometry.size.height / CGFloat(maxValue)

                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    path.addLine(to: CGPoint(
                        x: 0,
                        y: geometry.size.height - CGFloat(data[0]) * stepY
                    ))

                    for (index, value) in data.enumerated().dropFirst() {
                        path.addLine(to: CGPoint(
                            x: CGFloat(index) * stepX,
                            y: geometry.size.height - CGFloat(value) * stepY
                        ))
                    }

                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(AppState())
        .frame(width: 800, height: 900)
}

#Preview("Stat Card") {
    HStack {
        StatCard(
            title: "Total Uploads",
            value: "1,247",
            icon: "arrow.up.circle.fill",
            color: .blue,
            trend: .up(12)
        )
        StatCard(
            title: "Success Rate",
            value: "99.2%",
            icon: "checkmark.circle.fill",
            color: .green,
            trend: .down(2)
        )
    }
    .padding()
}

#Preview("Speed Graph") {
    SpeedGraphWidget()
        .frame(width: 300)
        .padding()
}
