import SwiftUI
import ShotDropperCore
import QuickLookThumbnailing

// MARK: - File Thumbnail View

/// Displays a thumbnail preview of a file, with fallback to file type icon
struct FileThumbnailView: View {
    let url: URL
    let size: ThumbnailSize
    var showOverlay: Bool = true

    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    enum ThumbnailSize {
        case small   // 32x32
        case medium  // 48x48
        case large   // 64x64
        case extraLarge  // 128x128

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 64
            case .extraLarge: return 128
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 24
            case .large: return 32
            case .extraLarge: return 48
            }
        }
    }

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                // Actual thumbnail
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.dimension, height: size.dimension)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                if showOverlay {
                    // File type badge
                    fileTypeBadge
                }
            } else if isLoading {
                // Loading state
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: size.dimension, height: size.dimension)
                    .overlay(
                        ProgressView()
                            .scaleEffect(size == .small ? 0.5 : 0.7)
                    )
            } else {
                // Fallback to file type icon
                fileTypeIcon
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        case .extraLarge: return 12
        }
    }

    private var fileTypeBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(url.pathExtension.uppercased())
                    .font(.system(size: size == .small ? 6 : 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
        }
    }

    private var fileTypeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [categoryColor.opacity(0.2), categoryColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.dimension, height: size.dimension)

            Image(systemName: categoryIcon)
                .font(.system(size: size.iconSize))
                .foregroundStyle(categoryColor)
        }
    }

    private var category: FileCategory {
        FileCategory.fromExtension(url.pathExtension)
    }

    private var categoryColor: Color {
        switch category {
        case .nukeComp: return .purple
        case .imageSequence: return .blue
        case .video: return .pink
        case .audio: return .orange
        case .project: return .green
        case .other: return .gray
        }
    }

    private var categoryIcon: String {
        category.iconName
    }

    private func loadThumbnail() async {
        isLoading = true

        // Check if file type supports thumbnails
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "exr", "dpx", "mov", "mp4", "avi", "pdf"]
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            isLoading = false
            loadFailed = true
            return
        }

        // Generate thumbnail using QuickLook
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size.dimension * 2, height: size.dimension * 2),
            scale: 2.0,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            await MainActor.run {
                self.thumbnail = representation.nsImage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadFailed = true
            }
        }
    }
}

// MARK: - File Info Card

/// A card showing file information with thumbnail
struct FileInfoCard: View {
    let fileInfo: FileInfo
    let url: URL
    var showDetails: Bool = true

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            FileThumbnailView(url: url, size: .medium)

            // File details
            if showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileInfo.filename)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Size
                        Text(ByteCountFormatter.string(fromByteCount: fileInfo.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Category badge
                        Text(fileInfo.category.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15))
                            .foregroundStyle(categoryColor)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var categoryColor: Color {
        switch fileInfo.category {
        case .nukeComp: return .purple
        case .imageSequence: return .blue
        case .video: return .pink
        case .audio: return .orange
        case .project: return .green
        case .other: return .gray
        }
    }
}

// MARK: - Thumbnail Grid

/// A grid of file thumbnails
struct ThumbnailGrid: View {
    let files: [URL]
    let maxDisplay: Int
    var onFileSelected: ((URL) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(files.prefix(maxDisplay).enumerated()), id: \.offset) { index, url in
                    ThumbnailGridItem(url: url, index: index) {
                        onFileSelected?(url)
                    }
                }

                // Overflow indicator
                if files.count > maxDisplay {
                    OverflowIndicator(count: files.count - maxDisplay)
                }
            }
        }
    }
}

// MARK: - Thumbnail Grid Item

struct ThumbnailGridItem: View {
    let url: URL
    let index: Int
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                FileThumbnailView(url: url, size: .large)

                Text(url.lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(hasAppeared ? 1.0 : 0.8)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(Double(index) * 0.03)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Overflow Indicator

struct OverflowIndicator: View {
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 64, height: 64)

                Text("+\(count)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            Text("more files")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

// MARK: - Image Sequence Preview

/// Special preview for image sequences showing multiple frames
struct ImageSequencePreview: View {
    let frames: [URL]
    let frameCount: Int

    @State private var currentFrame = 0
    @State private var isPlaying = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            // Main preview
            ZStack {
                if let frameURL = frames[safe: currentFrame] {
                    FileThumbnailView(url: frameURL, size: .extraLarge, showOverlay: false)
                }

                // Frame counter
                VStack {
                    Spacer()
                    HStack {
                        Text("Frame \(currentFrame + 1)/\(frameCount)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())

                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    currentFrame = max(0, currentFrame - 1)
                } label: {
                    Image(systemName: "backward.frame")
                }
                .disabled(currentFrame == 0)

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }

                Button {
                    currentFrame = min(frames.count - 1, currentFrame + 1)
                } label: {
                    Image(systemName: "forward.frame")
                }
                .disabled(currentFrame == frames.count - 1)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/24.0, repeats: true) { _ in
            currentFrame = (currentFrame + 1) % frames.count
        }
    }

    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - File Drop Preview

/// Preview shown when files are about to be dropped
struct FileDropPreview: View {
    let files: [URL]

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 16) {
            // File count indicator
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.headline)
            }

            // Thumbnail preview
            HStack(spacing: -20) {
                ForEach(Array(files.prefix(4).enumerated()), id: \.offset) { index, url in
                    FileThumbnailView(url: url, size: .medium, showOverlay: false)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4)
                        .rotationEffect(.degrees(Double(index - 2) * 5))
                        .offset(y: CGFloat(index) * 2)
                        .zIndex(Double(4 - index))
                }

                if files.count > 4 {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 48, height: 48)

                        Text("+\(files.count - 4)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .offset(x: -10)
                }
            }

            // Total size
            Text(ByteCountFormatter.string(fromByteCount: computeTotalSize(), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
        )
        .scaleEffect(hasAppeared ? 1.0 : 0.9)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    private func computeTotalSize() -> Int64 {
        files.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return total + (size ?? 0)
        }
    }
}

// MARK: - Collection Extension

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("File Thumbnails") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            FileThumbnailView(url: URL(fileURLWithPath: "/tmp/test.nk"), size: .small)
            FileThumbnailView(url: URL(fileURLWithPath: "/tmp/test.exr"), size: .medium)
            FileThumbnailView(url: URL(fileURLWithPath: "/tmp/test.mov"), size: .large)
            FileThumbnailView(url: URL(fileURLWithPath: "/tmp/test.pdf"), size: .extraLarge)
        }

        FileInfoCard(
            fileInfo: FileInfo(
                filename: "SHOW_101_0010_comp_v005.nk",
                fileExtension: "nk",
                size: 1024 * 1024 * 15,
                category: .nukeComp,
                modificationDate: Date()
            ),
            url: URL(fileURLWithPath: "/tmp/test.nk")
        )
        .frame(width: 300)
    }
    .padding()
}

#Preview("Thumbnail Grid") {
    ThumbnailGrid(
        files: [
            URL(fileURLWithPath: "/tmp/file1.exr"),
            URL(fileURLWithPath: "/tmp/file2.nk"),
            URL(fileURLWithPath: "/tmp/file3.mov"),
            URL(fileURLWithPath: "/tmp/file4.pdf"),
            URL(fileURLWithPath: "/tmp/file5.jpg"),
            URL(fileURLWithPath: "/tmp/file6.png"),
        ],
        maxDisplay: 5
    )
    .frame(width: 400)
    .padding()
}

#Preview("File Drop Preview") {
    FileDropPreview(
        files: [
            URL(fileURLWithPath: "/tmp/file1.exr"),
            URL(fileURLWithPath: "/tmp/file2.nk"),
            URL(fileURLWithPath: "/tmp/file3.mov"),
        ]
    )
    .padding()
}
