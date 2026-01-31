import SwiftUI
import DragNDropCore

// MARK: - Help Button

/// A help button that shows contextual information
struct HelpButton: View {
    let title: String
    let content: String
    var learnMoreURL: URL? = nil

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .trailing) {
            HelpPopover(title: title, content: content, learnMoreURL: learnMoreURL)
        }
    }
}

// MARK: - Help Popover

struct HelpPopover: View {
    let title: String
    let content: String
    var learnMoreURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(title)
                    .font(.headline)
            }

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = learnMoreURL {
                Link(destination: url) {
                    HStack {
                        Text("Learn more")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Feature Callout

/// A callout bubble to highlight new or important features
struct FeatureCallout: View {
    let title: String
    let description: String
    let icon: String
    var onDismiss: (() -> Void)? = nil

    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("NEW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Dismiss button
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .scaleEffect(hasAppeared ? 1.0 : 0.9)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(0.5)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Quick Tip Card

struct QuickTipCard: View {
    let tip: QuickTip

    @State private var isHovered = false

    struct QuickTip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        var shortcut: String? = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tip.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(tip.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let shortcut = tip.shortcut {
                KeyboardShortcutBadge(shortcut: shortcut)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Keyboard Shortcut Badge

struct KeyboardShortcutBadge: View {
    let shortcut: String

    var body: some View {
        Text(shortcut)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Tips Panel

struct TipsPanel: View {
    @State private var currentTipIndex = 0

    let tips: [QuickTipCard.QuickTip] = [
        .init(icon: "folder", title: "Drop folders", description: "Drop entire folders to upload all files at once", shortcut: nil),
        .init(icon: "arrow.triangle.branch", title: "Auto-organize", description: "Files are automatically sorted by shot name", shortcut: nil),
        .init(icon: "keyboard", title: "Keyboard shortcuts", description: "Press Space to pause/resume uploads", shortcut: "Space"),
        .init(icon: "doc.on.doc", title: "Copy S3 URI", description: "Right-click any upload to copy its S3 path", shortcut: "Cmd+C"),
        .init(icon: "clock.arrow.circlepath", title: "Resume uploads", description: "Interrupted uploads automatically resume", shortcut: nil),
        .init(icon: "rectangle.badge.checkmark", title: "Finder integration", description: "Right-click files in Finder to upload", shortcut: nil),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quick Tips")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(AnimationPresets.snappy) {
                            currentTipIndex = max(0, currentTipIndex - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentTipIndex == 0)

                    Text("\(currentTipIndex + 1)/\(tips.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(AnimationPresets.snappy) {
                            currentTipIndex = min(tips.count - 1, currentTipIndex + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentTipIndex == tips.count - 1)
                }
            }

            QuickTipCard(tip: tips[currentTipIndex])
                .id(currentTipIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Walkthrough Overlay

struct WalkthroughStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let highlightRect: CGRect?
    let arrowDirection: Edge
}

struct WalkthroughOverlay: View {
    let steps: [WalkthroughStep]
    @Binding var currentStep: Int
    var onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background with cutout
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                // Highlight area (if any)
                if let rect = steps[currentStep].highlightRect {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .frame(width: rect.width + 20, height: rect.height + 20)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                }

                // Tooltip card
                VStack(spacing: 16) {
                    // Step indicator
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 8, height: 8)
                        }
                    }

                    VStack(spacing: 8) {
                        Text(steps[currentStep].title)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(steps[currentStep].description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        if currentStep > 0 {
                            Button("Back") {
                                withAnimation(AnimationPresets.snappy) {
                                    currentStep -= 1
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }

                        Button(currentStep == steps.count - 1 ? "Done" : "Next") {
                            if currentStep == steps.count - 1 {
                                onComplete()
                            } else {
                                withAnimation(AnimationPresets.snappy) {
                                    currentStep += 1
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 20)
                )
                .frame(maxWidth: 320)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .compositingGroup()
        }
    }
}

// MARK: - Info Row

/// A row with a label and info button
struct InfoRow: View {
    let label: String
    let helpTitle: String
    let helpContent: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HelpButton(title: helpTitle, content: helpContent)
        }
    }
}

// MARK: - Contextual Help Topics

enum HelpTopic {
    case workflow
    case pathTemplate
    case extractionRules
    case scheduling
    case duplicateDetection
    case bandwidthThrottling
    case multipartUpload
    case presignedURLs
    case ssoLogin

    var title: String {
        switch self {
        case .workflow: return "Workflows"
        case .pathTemplate: return "Path Templates"
        case .extractionRules: return "Extraction Rules"
        case .scheduling: return "Upload Scheduling"
        case .duplicateDetection: return "Duplicate Detection"
        case .bandwidthThrottling: return "Bandwidth Throttling"
        case .multipartUpload: return "Multipart Uploads"
        case .presignedURLs: return "Presigned URLs"
        case .ssoLogin: return "AWS SSO Login"
        }
    }

    var content: String {
        switch self {
        case .workflow:
            return "Workflows define how files are organized when uploaded to S3. Each workflow has a bucket, region, and path template."
        case .pathTemplate:
            return "Path templates use placeholders like {SHOW} and {SHOT} that are filled in from the filename. Example: projects/{SHOW}/shots/{SHOT}/"
        case .extractionRules:
            return "Extraction rules use regex patterns to pull values from filenames. Capture groups map to placeholders in your path template."
        case .scheduling:
            return "Schedule uploads to run during specific times, like overnight or on weekends, to avoid consuming bandwidth during work hours."
        case .duplicateDetection:
            return "Checks if files already exist in S3 before uploading. You can choose to skip, warn, or overwrite duplicates."
        case .bandwidthThrottling:
            return "Limit upload speed to leave bandwidth available for other work. Set a maximum MB/s rate for all uploads."
        case .multipartUpload:
            return "Large files are automatically split into parts and uploaded in parallel for faster transfer and resumable uploads."
        case .presignedURLs:
            return "Generate temporary shareable links to uploaded files. Recipients can download without AWS credentials."
        case .ssoLogin:
            return "AWS SSO lets you sign in using your organization's identity provider. Enter your SSO start URL to begin."
        }
    }
}

struct HelpTopicButton: View {
    let topic: HelpTopic

    var body: some View {
        HelpButton(title: topic.title, content: topic.content)
    }
}

// MARK: - Preview

#Preview("Help Components") {
    VStack(spacing: 20) {
        HelpButton(title: "Test Help", content: "This is some helpful information about the feature.")

        FeatureCallout(
            title: "Upload Scheduling",
            description: "Schedule uploads to run during off-hours",
            icon: "clock"
        )

        TipsPanel()

        QuickTipCard(tip: .init(
            icon: "keyboard",
            title: "Quick shortcut",
            description: "Press Space to pause uploads",
            shortcut: "Space"
        ))
    }
    .padding()
    .frame(width: 400)
}
