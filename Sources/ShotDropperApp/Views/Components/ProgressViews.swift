import SwiftUI
import ShotDropperCore

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat
    var showPercentage: Bool = true
    var gradientColors: [Color] = [.accentColor, .purple]

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(
                    Color.secondary.opacity(0.2),
                    lineWidth: lineWidth
                )

            // Progress circle with angular gradient
            Circle()
                .trim(from: 0, to: animatedProgress / 100)
                .stroke(
                    AngularGradient(
                        colors: gradientColors + [gradientColors.first ?? .accentColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Percentage text with animation
            if showPercentage {
                Text("\(Int(animatedProgress))%")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(AnimationPresets.smooth) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Upload Speed Indicator

struct UploadSpeedIndicator: View {
    let bytesPerSecond: Double

    private var formattedSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(formattedSpeed)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - File Type Icon

struct FileTypeIcon: View {
    let category: FileCategory
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(categoryColor.opacity(0.15))
                .frame(width: size, height: size)

            Image(systemName: category.iconName)
                .font(.system(size: size * 0.45))
                .foregroundStyle(categoryColor)
        }
    }

    private var categoryColor: Color {
        switch category {
        case .nukeComp: return .orange
        case .imageSequence: return .purple
        case .video: return .blue
        case .audio: return .green
        case .project: return .yellow
        case .other: return .gray
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: UploadStatus
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                // Pulsing background for active states
                if status == .uploading || status == .preparing {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(isAnimating ? 1.5 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                }

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(status.rawValue)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
        .onAppear {
            if status == .uploading || status == .preparing {
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .uploading || newStatus == .preparing {
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .gray
        case .preparing: return .yellow
        case .uploading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Animated Upload Icon

struct AnimatedUploadIcon: View {
    @State private var isAnimating = false
    let isUploading: Bool

    var body: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.title)
            .foregroundStyle(Color.accentColor)
            .offset(y: isAnimating ? -3 : 0)
            .animation(
                isUploading
                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onAppear {
                isAnimating = isUploading
            }
            .onChange(of: isUploading) { _, newValue in
                isAnimating = newValue
            }
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(isPulsing ? 2 : 1)
                    .opacity(isPulsing ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Time Remaining Label

struct TimeRemainingLabel: View {
    let seconds: TimeInterval?

    private var formattedTime: String? {
        guard let seconds = seconds, seconds > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    var body: some View {
        if let time = formattedTime {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bytes Transferred Label

struct BytesTransferredLabel: View {
    let uploaded: Int64
    let total: Int64

    private var uploadedFormatted: String {
        ByteCountFormatter.string(fromByteCount: uploaded, countStyle: .file)
    }

    private var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var body: some View {
        Text("\(uploadedFormatted) / \(totalFormatted)")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

// MARK: - Retry Badge

struct RetryBadge: View {
    let retryAttempts: Int
    let maxRetries: Int

    var body: some View {
        if retryAttempts > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                Text("\(retryAttempts)/\(maxRetries)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Retry Status View

struct RetryStatusView: View {
    let job: UploadJob
    let maxRetries: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if job.retryAttempts > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.orange)
                    Text("Retry attempt \(job.retryAttempts) of \(maxRetries)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastRetry = job.lastRetryAt {
                    Text("Last retry: \(lastRetry, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !job.retryErrors.isEmpty, let lastError = job.retryErrors.last {
                    Text("Last error: \(lastError)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Exponential Backoff Indicator

struct BackoffIndicator: View {
    let delaySeconds: Int
    @State private var countdown: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.xmark")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("Retrying in \(countdown)s...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onAppear {
            countdown = delaySeconds
        }
        .task {
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
        }
    }
}

// MARK: - Compact Upload Row

struct CompactUploadRow: View {
    let job: UploadJob
    let onCancel: () -> Void
    var maxRetries: Int = 3

    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(category: job.fileInfo.category, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(job.displayName)
                        .font(.caption)
                        .lineLimit(1)

                    if job.retryAttempts > 0 {
                        RetryBadge(retryAttempts: job.retryAttempts, maxRetries: maxRetries)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: job.retryAttempts > 0
                                    ? [.orange, .yellow]
                                    : [.accentColor, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * (job.progress.percentage / 100))
                            .animation(AnimationPresets.smooth, value: job.progress.percentage)
                    }
                }
                .frame(height: 4)
            }

            Text("\(Int(job.progress.percentage))%")
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Progress Views") {
    VStack(spacing: 20) {
        CircularProgressView(progress: 67.5, lineWidth: 4)
            .frame(width: 50, height: 50)

        UploadSpeedIndicator(bytesPerSecond: 12_500_000)

        FileTypeIcon(category: .nukeComp, size: 40)

        StatusBadge(status: .uploading)

        AnimatedUploadIcon(isUploading: true)

        PulsingDot(color: .green)

        TimeRemainingLabel(seconds: 3720)

        BytesTransferredLabel(uploaded: 52_428_800, total: 104_857_600)

        RetryBadge(retryAttempts: 2, maxRetries: 3)

        BackoffIndicator(delaySeconds: 15)
    }
    .padding()
}
