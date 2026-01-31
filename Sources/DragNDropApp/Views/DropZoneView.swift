import SwiftUI
import UniformTypeIdentifiers
import DragNDropCore

// MARK: - Drop Zone View

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false
    @State private var isDragging = false
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // Animated glass background
            GlassBackground(cornerRadius: 16, opacity: 0.1)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8, 4])
                        )
                )
                .glow(color: isTargeted ? .accentColor : .clear, radius: isTargeted ? 15 : 0)

            // Content
            DropZoneContent(isTargeted: isTargeted)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            let urls = await loadURLs(from: providers)
            await appState.processDroppedFiles(urls)
        }
    }
}

// MARK: - Drop Zone Content

private struct DropZoneContent: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .symbolEffect(.bounce, value: isTargeted)

            VStack(spacing: 4) {
                Text(isTargeted ? "Release to Add" : "Drop Files Here")
                    .font(.headline)
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)

                Text("Nuke comps, renders, videos, sequences")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scaleEffect(isTargeted ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isTargeted)
    }
}

// MARK: - Large Drop Zone (for main window)

struct LargeDropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            LargeDropZoneBackground(isTargeted: isTargeted)
            LargeDropZoneAnimatedCircles(isTargeted: isTargeted)
            LargeDropZoneMainContent(isTargeted: isTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            let urls = await loadURLs(from: providers)
            await appState.processDroppedFiles(urls)
        }
    }
}

// MARK: - Large Drop Zone Components

private struct LargeDropZoneBackground: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: borderColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isTargeted ? 3 : 2
                    )
            )
            .shadow(color: shadowColor, radius: 20)
    }

    private var borderColors: [Color] {
        if isTargeted {
            return [Color.accentColor, Color.purple, Color.accentColor]
        } else {
            return [Color.secondary.opacity(0.3), Color.secondary.opacity(0.2)]
        }
    }

    private var shadowColor: Color {
        isTargeted ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.1)
    }
}

private struct LargeDropZoneAnimatedCircles: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            ForEach(0..<3, id: \.self) { i in
                AnimatedCircle(index: i, isTargeted: isTargeted)
            }
        }
    }
}

private struct AnimatedCircle: View {
    let index: Int
    let isTargeted: Bool

    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
            .frame(width: 100 + CGFloat(index * 40), height: 100 + CGFloat(index * 40))
            .scaleEffect(isTargeted ? 1.5 : 1.0)
            .opacity(isTargeted ? 0 : 1)
            .animation(
                .easeOut(duration: 1.5)
                .repeatForever(autoreverses: false)
                .delay(Double(index) * 0.3),
                value: isTargeted
            )
    }
}

private struct LargeDropZoneMainContent: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 20) {
            LargeDropZoneIcon(isTargeted: isTargeted)
            LargeDropZoneText(isTargeted: isTargeted)
            FileTypeBadgesRow()
        }
        .padding(40)
        .scaleEffect(isTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isTargeted)
    }
}

private struct LargeDropZoneIcon: View {
    let isTargeted: Bool
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Pulsing background rings
            if isTargeted {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(isAnimating ? 1.5 + CGFloat(i) * 0.3 : 1.0)
                        .opacity(isAnimating ? 0 : 0.5)
                }
            }

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 100, height: 100)
                .glow(color: isTargeted ? .accentColor : .clear, radius: 10)

            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                .font(.system(size: 44))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .symbolEffect(.bounce, value: isTargeted)
        }
        .onChange(of: isTargeted) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }
}

private struct LargeDropZoneText: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(isTargeted ? "Release to Add Files" : "Drop Your Files Here")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)

            Text("Supports Nuke comps (.nk), renders (EXR, TIFF, PNG),\nvideos (MOV, MP4), and image sequences")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct FileTypeBadgesRow: View {
    var body: some View {
        HStack(spacing: 12) {
            FileTypeBadge(icon: "wand.and.rays", text: "Nuke", color: .orange)
                .animatedAppearance(delay: 0.1)
            FileTypeBadge(icon: "photo.stack", text: "Sequences", color: .purple)
                .animatedAppearance(delay: 0.2)
            FileTypeBadge(icon: "film", text: "Video", color: .blue)
                .animatedAppearance(delay: 0.3)
            FileTypeBadge(icon: "waveform", text: "Audio", color: .green)
                .animatedAppearance(delay: 0.4)
        }
        .padding(.top, 8)
    }
}

// MARK: - File Type Badge

struct FileTypeBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - URL Loading Helper

/// Thread-safe URL collector for drag and drop operations
private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    func getURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

@MainActor
private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
    await withCheckedContinuation { continuation in
        let collector = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            continuation.resume(returning: collector.getURLs())
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        DropZoneView()
            .frame(height: 140)
            .padding()

        LargeDropZoneView()
            .frame(height: 300)
            .padding()
    }
    .environmentObject(AppState())
}
