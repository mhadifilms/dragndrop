import SwiftUI
import ShotDropperCore

// MARK: - Empty State View

/// A reusable empty state view with illustration and action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var style: EmptyStateStyle = .default

    @State private var hasAppeared = false
    @State private var iconScale: CGFloat = 0.8
    @State private var iconRotation: Double = -5

    enum EmptyStateStyle {
        case `default`
        case compact
        case large
        case illustration
    }

    var body: some View {
        VStack(spacing: spacing) {
            // Animated icon
            iconView
                .scaleEffect(hasAppeared ? 1.0 : iconScale)
                .rotationEffect(.degrees(hasAppeared ? 0 : iconRotation))

            // Text content
            VStack(spacing: 6) {
                Text(title)
                    .font(titleFont)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)

                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
            }
            .animation(AnimationPresets.spring.delay(0.1), value: hasAppeared)

            // Actions
            if actionTitle != nil || secondaryActionTitle != nil {
                HStack(spacing: 12) {
                    if let actionTitle = actionTitle, let action = action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(style == .compact ? .small : .regular)
                    }

                    if let secondaryActionTitle = secondaryActionTitle, let secondaryAction = secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .controlSize(style == .compact ? .small : .regular)
                    }
                }
                .padding(.top, 8)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 15)
                .animation(AnimationPresets.spring.delay(0.2), value: hasAppeared)
            }
        }
        .padding(padding)
        .frame(maxWidth: maxWidth, maxHeight: .infinity)
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        switch style {
        case .illustration:
            IllustratedIcon(systemName: icon, size: iconSize)
        default:
            ZStack {
                // Glow effect
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: iconSize * 1.8, height: iconSize * 1.8)
                    .blur(radius: 10)

                // Icon background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconSize * 1.5, height: iconSize * 1.5)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: iconSize * 0.6))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Style Properties

    private var iconSize: CGFloat {
        switch style {
        case .compact: return 48
        case .default: return 64
        case .large, .illustration: return 80
        }
    }

    private var spacing: CGFloat {
        switch style {
        case .compact: return 12
        case .default: return 16
        case .large, .illustration: return 24
        }
    }

    private var padding: CGFloat {
        switch style {
        case .compact: return 16
        case .default: return 24
        case .large, .illustration: return 32
        }
    }

    private var maxWidth: CGFloat? {
        switch style {
        case .compact: return 280
        case .default: return 320
        case .large, .illustration: return 400
        }
    }

    private var titleFont: Font {
        switch style {
        case .compact: return .subheadline
        case .default: return .headline
        case .large, .illustration: return .title3
        }
    }

    private var subtitleFont: Font {
        switch style {
        case .compact: return .caption
        case .default: return .subheadline
        case .large, .illustration: return .body
        }
    }
}

// MARK: - Illustrated Icon

struct IllustratedIcon: View {
    let systemName: String
    let size: CGFloat

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.accentColor, .purple, .blue, .accentColor],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: isAnimating)

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)

            // Icon
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Predefined Empty States

struct NoUploadsEmptyState: View {
    var onDropFiles: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "arrow.up.circle",
            title: "No Active Uploads",
            subtitle: "Drop files onto the window or use the drop zone to start uploading to S3.",
            actionTitle: "Open Drop Zone",
            action: onDropFiles,
            style: .default
        )
    }
}

struct NoHistoryEmptyState: View {
    var body: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "No Upload History",
            subtitle: "Your completed uploads will appear here. Start by dropping some files to upload.",
            style: .large
        )
    }
}

struct NoSearchResultsEmptyState: View {
    let searchText: String
    var onClearSearch: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: "No uploads match \"\(searchText)\". Try a different search term.",
            actionTitle: "Clear Search",
            action: onClearSearch,
            style: .compact
        )
    }
}

struct NoWorkflowEmptyState: View {
    var onCreateWorkflow: (() -> Void)? = nil
    var onSelectWorkflow: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "folder.badge.gearshape",
            title: "No Workflow Selected",
            subtitle: "Create or select a workflow to define where your files will be uploaded.",
            actionTitle: "Create Workflow",
            action: onCreateWorkflow,
            secondaryActionTitle: "Select Existing",
            secondaryAction: onSelectWorkflow,
            style: .illustration
        )
    }
}

struct NotAuthenticatedEmptyState: View {
    var onSignIn: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "person.crop.circle.badge.exclamationmark",
            title: "Sign In Required",
            subtitle: "Connect your AWS account to start uploading files to S3.",
            actionTitle: "Sign In with AWS SSO",
            action: onSignIn,
            style: .illustration
        )
    }
}

struct QueueEmptyState: View {
    var body: some View {
        EmptyStateView(
            icon: "list.bullet.rectangle",
            title: "Queue is Empty",
            subtitle: "Files waiting to be uploaded will appear here.",
            style: .compact
        )
    }
}

struct ConnectionErrorEmptyState: View {
    let errorMessage: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Error icon with pulse
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
            }
            .pulse(duration: 2.0)

            Text("Connection Error")
                .font(.headline)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let onRetry = onRetry {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
    }
}

// MARK: - Upload Complete State

struct UploadCompleteState: View {
    let uploadCount: Int
    let totalSize: Int64
    var onViewHistory: (() -> Void)? = nil
    var onUploadMore: (() -> Void)? = nil

    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: 20) {
            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)

                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 3)
                    .frame(width: 100, height: 100)

                if showCheckmark {
                    AnimatedCheckmark(color: .green)
                        .frame(width: 50, height: 50)
                }
            }

            VStack(spacing: 8) {
                Text("Upload Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 4) {
                    Text("\(uploadCount)")
                        .fontWeight(.semibold)
                    Text(uploadCount == 1 ? "file" : "files")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let onViewHistory = onViewHistory {
                    Button("View History", action: onViewHistory)
                        .buttonStyle(.bordered)
                }

                if let onUploadMore = onUploadMore {
                    Button("Upload More", action: onUploadMore)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(0.2)) {
                showCheckmark = true
            }
        }
    }
}

// MARK: - Skeleton Loading States

struct UploadRowSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon skeleton
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 180, height: 14)

                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 120, height: 10)
            }

            Spacer()

            // Progress skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 50, height: 14)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shimmer()
        .onAppear {
            isAnimating = true
        }
    }
}

struct HistoryListSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                UploadRowSkeleton()
                    .opacity(1.0 - Double(index) * 0.15)
            }
        }
        .padding()
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    let type: BannerType
    let message: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil

    @State private var isVisible = true

    enum BannerType {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .foregroundStyle(type.color)

                Text(message)
                    .font(.subheadline)

                Spacer()

                if let action = action, let actionTitle = actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Button {
                    withAnimation(AnimationPresets.snappy) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(type.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(type.color.opacity(0.3), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Tooltip Modifier

struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(AnimationPresets.snappy) {
                    isShowing = hovering
                }
            }
            .overlay(alignment: .top) {
                if isShowing {
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .offset(y: -35)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

// MARK: - Preview

#Preview("Empty States") {
    ScrollView {
        VStack(spacing: 40) {
            NoUploadsEmptyState()
            Divider()
            NoHistoryEmptyState()
            Divider()
            NoWorkflowEmptyState()
            Divider()
            NotAuthenticatedEmptyState()
            Divider()
            UploadCompleteState(uploadCount: 5, totalSize: 1024 * 1024 * 150)
        }
        .padding()
    }
    .frame(width: 500, height: 800)
}

#Preview("Skeleton Loading") {
    HistoryListSkeleton()
        .frame(width: 400)
        .padding()
}

#Preview("Status Banners") {
    VStack(spacing: 12) {
        StatusBanner(type: .info, message: "New version available", action: {}, actionTitle: "Update")
        StatusBanner(type: .success, message: "All files uploaded successfully")
        StatusBanner(type: .warning, message: "Some files were skipped")
        StatusBanner(type: .error, message: "Connection lost", action: {}, actionTitle: "Retry")
    }
    .padding()
    .frame(width: 450)
}
