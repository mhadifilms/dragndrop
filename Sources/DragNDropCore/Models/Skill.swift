import Foundation

// MARK: - Skill Status

/// Status of skill execution for an upload job
public enum SkillStatus: Equatable, Sendable {
    case notStarted
    case running(currentSkill: String, completed: Int, total: Int)
    case completed(count: Int)
    case failed(error: String)
    case skipped  // Skills disabled or not applicable

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .notStarted:
            return ""
        case .running(let skill, let completed, let total):
            return "Running \(skill)... (\(completed)/\(total))"
        case .completed(let count):
            return count == 0 ? "" : "\(count) companion file\(count == 1 ? "" : "s")"
        case .failed(let error):
            return "Skills failed: \(error)"
        case .skipped:
            return ""
        }
    }
}

// MARK: - Skill Output Type

public enum SkillOutputType: String, Codable, CaseIterable, Sendable {
    case image = "Image"
    case video = "Video"
    case text = "Text"
    case checksum = "Checksum"

    public var iconName: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .text: return "doc.text"
        case .checksum: return "number"
        }
    }
}

// MARK: - Skill Model

/// A skill that generates companion files during upload
public struct Skill: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var enabled: Bool
    public var isBuiltIn: Bool
    public var script: String
    public var applicableExtensions: [String]  // Empty = all files
    public var outputSuffix: String            // e.g., "_thumb.png"
    public var outputType: SkillOutputType
    public var timeoutSeconds: Int             // Default: 300 (5 minutes)

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        enabled: Bool = false,
        isBuiltIn: Bool = false,
        script: String,
        applicableExtensions: [String] = [],
        outputSuffix: String,
        outputType: SkillOutputType,
        timeoutSeconds: Int = 300
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
        self.script = script
        self.applicableExtensions = applicableExtensions
        self.outputSuffix = outputSuffix
        self.outputType = outputType
        self.timeoutSeconds = timeoutSeconds
    }

    /// Checks if this skill applies to a given file extension
    public func appliesTo(fileExtension: String) -> Bool {
        guard !applicableExtensions.isEmpty else { return true }
        return applicableExtensions.contains(fileExtension.lowercased())
    }

    /// SF Symbol icon for the skill based on its name/type
    public var iconName: String {
        let n = name.lowercased()
        switch n {
        case let s where s.contains("thumbnail"): return "photo.fill"
        case let s where s.contains("proxy") && s.contains("prores"): return "film.stack"
        case let s where s.contains("checksum"): return "number.square"
        case let s where s.contains("hdr"): return "sun.max.fill"
        case let s where s.contains("audio") && s.contains("extract"): return "waveform"
        case let s where s.contains("gif"): return "photo.on.rectangle.angled"
        case let s where s.contains("media info") || s.contains("info"): return "info.circle"
        case let s where s.contains("first") && s.contains("frame"): return "backward.frame"
        case let s where s.contains("last") && s.contains("frame"): return "forward.frame"
        case let s where s.contains("h.264") || s.contains("h264") || s.contains("preview"): return "play.rectangle"
        case let s where s.contains("contact") && s.contains("sheet"): return "square.grid.3x3"
        case let s where s.contains("waveform"): return "waveform.path.ecg"
        default: return outputType.iconName
        }
    }
}

// MARK: - Built-in Skills

extension Skill {
    /// All built-in skills that come with the app
    public static let builtInSkills: [Skill] = [
        thumbnailSkill,
        proResProxySkill,
        checksumSkill,
        hdrTaggingSkill,
        audioExtractSkill,
        gifPreviewSkill,
        mediaInfoSkill,
        firstFrameSkill,
        lastFrameSkill,
        h264PreviewSkill,
        contactSheetSkill,
        waveformSkill
    ]

    /// Built-in skill IDs (stable across app versions)
    public static let thumbnailSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let proResProxySkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    public static let checksumSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    public static let hdrTaggingSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    public static let audioExtractSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    public static let gifPreviewSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    public static let mediaInfoSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    public static let firstFrameSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    public static let lastFrameSkillId = UUID(uuidString: "00000000-0000-0000-0000-00000000000c")!
    public static let h264PreviewSkillId = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    public static let contactSheetSkillId = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
    public static let waveformSkillId = UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!

    /// Thumbnail PNG - Generate thumbnail for videos
    public static let thumbnailSkill = Skill(
        id: thumbnailSkillId,
        name: "Thumbnail PNG",
        description: "Generate a thumbnail image for video uploads",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Generate thumbnail from video at 1 second mark
# Output: {filename}_thumb.png

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_thumb.png"

"$FFMPEG" -y -i "$INPUT_FILE" -ss 00:00:01.000 -vframes 1 -vf "scale=480:-1" "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Thumbnail created: $OUTPUT_FILE"
else
    echo "Failed to create thumbnail" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_thumb.png",
        outputType: .image,
        timeoutSeconds: 60
    )

    /// ProRes Proxy - Create lightweight proxy video
    public static let proResProxySkill = Skill(
        id: proResProxySkillId,
        name: "ProRes Proxy",
        description: "Create a lightweight ProRes proxy video",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Create ProRes Proxy from video
# Output: {filename}_proxy.mov

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_proxy.mov"

"$FFMPEG" -y -i "$INPUT_FILE" -c:v prores_ks -profile:v 0 -vf "scale=1280:-1" -c:a pcm_s16le "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Proxy created: $OUTPUT_FILE"
else
    echo "Failed to create proxy" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v"],
        outputSuffix: "_proxy.mov",
        outputType: .video,
        timeoutSeconds: 600  // 10 minutes for proxy generation
    )

    /// Checksum - Generate MD5/SHA256 checksum file
    public static let checksumSkill = Skill(
        id: checksumSkillId,
        name: "Checksum",
        description: "Generate MD5 and SHA256 checksum file",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Generate MD5 and SHA256 checksums
# Output: {filename}.checksum

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}.checksum"

echo "# Checksums for: $FILENAME" > "$OUTPUT_FILE"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

MD5=$(md5 -q "$INPUT_FILE")
echo "MD5: $MD5" >> "$OUTPUT_FILE"

SHA256=$(shasum -a 256 "$INPUT_FILE" | awk '{print $1}')
echo "SHA256: $SHA256" >> "$OUTPUT_FILE"

echo "Checksum file created: $OUTPUT_FILE"
""",
        applicableExtensions: [],  // All files
        outputSuffix: ".checksum",
        outputType: .checksum,
        timeoutSeconds: 300  // 5 minutes for large files
    )

    /// HDR Tagging - Tag SDR video with P3-D65 HDR10 metadata
    public static let hdrTaggingSkill = Skill(
        id: hdrTaggingSkillId,
        name: "HDR Tagging",
        description: "Tag SDR video with P3-D65 HDR10 metadata",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Tag video with HDR10 metadata (P3-D65 color space)
# Output: {filename}_hdr.mov

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_hdr.mov"

"$FFMPEG" -y -i "$INPUT_FILE" \\
    -c:v copy -c:a copy \\
    -color_primaries bt2020 \\
    -color_trc smpte2084 \\
    -colorspace bt2020nc \\
    -metadata:s:v:0 "mastering-display-color-primaries=P3-D65" \\
    "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "HDR tagged video created: $OUTPUT_FILE"
else
    echo "Failed to create HDR tagged video" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "mxf"],
        outputSuffix: "_hdr.mov",
        outputType: .video,
        timeoutSeconds: 120
    )

    /// Audio Extract - Extract audio track as WAV
    public static let audioExtractSkill = Skill(
        id: audioExtractSkillId,
        name: "Audio Extract",
        description: "Extract audio track as WAV file",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Extract audio track from video as WAV
# Output: {filename}_audio.wav

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_audio.wav"

# Check if file has audio
HAS_AUDIO=$("$FFPROBE" -i "$INPUT_FILE" -show_streams -select_streams a -loglevel error 2>&1 | grep -c "codec_type=audio" || true)

if [ "$HAS_AUDIO" -eq 0 ]; then
    echo "No audio track found in file" >&2
    exit 0
fi

"$FFMPEG" -y -i "$INPUT_FILE" -vn -acodec pcm_s16le -ar 48000 -ac 2 "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Audio extracted: $OUTPUT_FILE"
else
    echo "Failed to extract audio" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_audio.wav",
        outputType: .video,  // Using video type for audio files
        timeoutSeconds: 300
    )

    /// GIF Preview - Create animated GIF preview
    public static let gifPreviewSkill = Skill(
        id: gifPreviewSkillId,
        name: "GIF Preview",
        description: "Create animated GIF preview (10 fps, 320px)",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Create animated GIF preview
# Output: {filename}_preview.gif

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_preview.gif"
PALETTE="${OUTPUT_DIR}/palette_temp.png"

# Get video duration
DURATION=$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)

# Limit to first 10 seconds or full duration if shorter
if [ "$DURATION" -gt 10 ]; then
    DURATION=10
fi

# Generate palette for better quality
"$FFMPEG" -y -t "$DURATION" -i "$INPUT_FILE" -vf "fps=10,scale=320:-1:flags=lanczos,palettegen" "$PALETTE" 2>/dev/null

# Create GIF using palette
"$FFMPEG" -y -t "$DURATION" -i "$INPUT_FILE" -i "$PALETTE" -filter_complex "fps=10,scale=320:-1:flags=lanczos[x];[x][1:v]paletteuse" "$OUTPUT_FILE" 2>/dev/null

# Cleanup palette
rm -f "$PALETTE"

if [ -f "$OUTPUT_FILE" ]; then
    echo "GIF preview created: $OUTPUT_FILE"
else
    echo "Failed to create GIF preview" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_preview.gif",
        outputType: .image,
        timeoutSeconds: 180
    )

    /// Media Info - Generate detailed media information report
    public static let mediaInfoSkill = Skill(
        id: mediaInfoSkillId,
        name: "Media Info",
        description: "Generate detailed media information report",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Generate detailed media information report
# Output: {filename}_info.txt

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_info.txt"

echo "========================================" > "$OUTPUT_FILE"
echo "Media Information Report" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "File: $FILENAME" >> "$OUTPUT_FILE"
echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
echo "Format Information" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
"$FFPROBE" -v error -show_format "$INPUT_FILE" 2>/dev/null >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
echo "Stream Information" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
"$FFPROBE" -v error -show_streams "$INPUT_FILE" 2>/dev/null >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
echo "Frame Information (first 5 frames)" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"
"$FFPROBE" -v error -select_streams v:0 -show_frames -read_intervals "%+#5" "$INPUT_FILE" 2>/dev/null >> "$OUTPUT_FILE" || true

if [ -f "$OUTPUT_FILE" ]; then
    echo "Media info report created: $OUTPUT_FILE"
else
    echo "Failed to create media info report" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm", "exr", "dpx", "tif", "tiff", "png", "jpg", "jpeg"],
        outputSuffix: "_info.txt",
        outputType: .text,
        timeoutSeconds: 60
    )

    /// First Frame - Extract first frame as PNG
    public static let firstFrameSkill = Skill(
        id: firstFrameSkillId,
        name: "First Frame",
        description: "Extract first frame as PNG image",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Extract first frame as PNG
# Output: {filename}_first.png

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_first.png"

"$FFMPEG" -y -i "$INPUT_FILE" -vframes 1 -vf "scale=1920:-1" "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "First frame: $OUTPUT_FILE"
else
    echo "Failed to extract first frame" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_first.png",
        outputType: .image,
        timeoutSeconds: 60
    )

    /// Last Frame - Extract last frame as PNG
    public static let lastFrameSkill = Skill(
        id: lastFrameSkillId,
        name: "Last Frame",
        description: "Extract last frame as PNG image",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Extract last frame as PNG
# Output: {filename}_last.png

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_last.png"

# Get video duration
DURATION=$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)

# Seek to near end and extract last frame
SEEK_TIME=$(echo "$DURATION - 0.1" | bc 2>/dev/null || echo "$DURATION")
"$FFMPEG" -y -ss "$SEEK_TIME" -i "$INPUT_FILE" -vframes 1 -vf "scale=1920:-1" "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Last frame: $OUTPUT_FILE"
else
    echo "Failed to extract last frame" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_last.png",
        outputType: .image,
        timeoutSeconds: 60
    )

    /// H.264 Preview - Create web-friendly H.264 preview
    public static let h264PreviewSkill = Skill(
        id: h264PreviewSkillId,
        name: "H.264 Preview",
        description: "Create web-friendly H.264 MP4 preview (720p)",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Create H.264 MP4 preview for web viewing
# Output: {filename}_preview.mp4

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_preview.mp4"

"$FFMPEG" -y -i "$INPUT_FILE" \\
    -c:v libx264 -preset fast -crf 23 \\
    -vf "scale=1280:-2" \\
    -c:a aac -b:a 128k \\
    -movflags +faststart \\
    "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "H.264 preview created: $OUTPUT_FILE"
else
    echo "Failed to create H.264 preview" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "prores"],
        outputSuffix: "_preview.mp4",
        outputType: .video,
        timeoutSeconds: 600
    )

    /// Contact Sheet - Generate contact sheet of video frames
    public static let contactSheetSkill = Skill(
        id: contactSheetSkillId,
        name: "Contact Sheet",
        description: "Generate contact sheet with 16 frames (4x4 grid)",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Generate contact sheet with 16 frames in 4x4 grid
# Output: {filename}_contactsheet.jpg

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_contactsheet.jpg"

# Get video duration
DURATION=$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)

# Calculate frame interval (16 frames evenly distributed)
INTERVAL=$(echo "$DURATION / 17" | bc -l 2>/dev/null || echo "1")

"$FFMPEG" -y -i "$INPUT_FILE" \\
    -vf "select='isnan(prev_selected_t)+gte(t-prev_selected_t\\,$INTERVAL)',scale=480:-1,tile=4x4" \\
    -frames:v 1 \\
    -q:v 2 \\
    "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Contact sheet created: $OUTPUT_FILE"
else
    echo "Failed to create contact sheet" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm"],
        outputSuffix: "_contactsheet.jpg",
        outputType: .image,
        timeoutSeconds: 120
    )

    /// Waveform - Generate audio waveform visualization
    public static let waveformSkill = Skill(
        id: waveformSkillId,
        name: "Audio Waveform",
        description: "Generate audio waveform visualization image",
        enabled: false,
        isBuiltIn: true,
        script: """
#!/bin/bash
# Generate audio waveform visualization
# Output: {filename}_waveform.png

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_waveform.png"

# Check if file has audio
HAS_AUDIO=$("$FFPROBE" -i "$INPUT_FILE" -show_streams -select_streams a -loglevel error 2>&1 | grep -c "codec_type=audio" || true)

if [ "$HAS_AUDIO" -eq 0 ]; then
    echo "No audio track found in file" >&2
    exit 0
fi

"$FFMPEG" -y -i "$INPUT_FILE" \\
    -filter_complex "showwavespic=s=1920x240:colors=#3498db|#2ecc71" \\
    -frames:v 1 \\
    "$OUTPUT_FILE" 2>/dev/null

if [ -f "$OUTPUT_FILE" ]; then
    echo "Waveform created: $OUTPUT_FILE"
else
    echo "Failed to create waveform" >&2
    exit 1
fi
""",
        applicableExtensions: ["mov", "mp4", "avi", "mkv", "mxf", "m4v", "webm", "wav", "mp3", "aac", "flac", "aiff"],
        outputSuffix: "_waveform.png",
        outputType: .image,
        timeoutSeconds: 120
    )
}

// MARK: - Companion File

/// A file generated by a skill that should be uploaded alongside the original
public struct CompanionFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let skillId: UUID
    public let skillName: String
    public let outputType: SkillOutputType

    public init(
        id: UUID = UUID(),
        url: URL,
        skillId: UUID,
        skillName: String,
        outputType: SkillOutputType
    ) {
        self.id = id
        self.url = url
        self.skillId = skillId
        self.skillName = skillName
        self.outputType = outputType
    }

    public var filename: String {
        url.lastPathComponent
    }

    public var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - Skill Execution Result

/// Result of executing a skill
public struct SkillExecutionResult: Sendable {
    public let skillId: UUID
    public let skillName: String
    public let success: Bool
    public let outputFile: URL?
    public let error: String?
    public let duration: TimeInterval
    public let stdout: String
    public let stderr: String

    public init(
        skillId: UUID,
        skillName: String,
        success: Bool,
        outputFile: URL? = nil,
        error: String? = nil,
        duration: TimeInterval,
        stdout: String = "",
        stderr: String = ""
    ) {
        self.skillId = skillId
        self.skillName = skillName
        self.success = success
        self.outputFile = outputFile
        self.error = error
        self.duration = duration
        self.stdout = stdout
        self.stderr = stderr
    }
}
