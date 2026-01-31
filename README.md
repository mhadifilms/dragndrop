# ShotDropper

A native macOS menu bar app for VFX artists to easily upload shots, renders, and compositing files to S3 with intelligent folder mapping.

## Features

### Core Functionality
- **Menu Bar App**: Lives in your menu bar, always accessible
- **Drag & Drop**: Simply drop files onto the drop zone
- **Smart Shot Detection**: Automatically extracts show/episode/shot info from filenames
- **Configurable Paths**: Flexible template system for any folder structure
- **Image Sequence Support**: Detects and uploads image sequences as groups

### Upload Features
- **Multipart Uploads**: Large files are split for reliable uploads
- **Resumable**: Interrupted uploads can be resumed
- **Parallel Uploads**: Configure concurrent upload count
- **Progress Tracking**: Real-time progress in menu bar
- **Background Uploads**: Continue working while uploads complete

### AWS Integration
- **SSO Authentication**: Login via AWS SSO with PKCE
- **Profile Support**: Use existing AWS CLI profiles
- **S3 Storage Classes**: Configure Standard, IA, Glacier, etc.
- **Server-Side Encryption**: Optional SSE-S3 or SSE-KMS

### Workflow Management
- **Workflow Presets**: Pre-configured workflows for common setups
- **Custom Workflows**: Create your own extraction patterns
- **Import/Export**: Share workflow configurations
- **Path Templates**: Flexible placeholders for dynamic paths

### Developer Features
- **CLI Tool**: Control uploads from command line
- **CLI Server**: Automate via local TCP server
- **Extensible**: Add support for other storage providers

## Installation

### Requirements
- macOS 15+ (macOS 26 Tahoe recommended for Liquid Glass UI)
- AWS account with S3 access
- Xcode 16+ (for building from source)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/your-org/dragndrop.git
cd dragndrop

# Build the app
swift build -c release

# Run the app
.build/release/ShotDropper
```

### Install CLI Tool

```bash
# Build and install the CLI
swift build -c release
cp .build/release/shotdrop /usr/local/bin/
```

## Configuration

### AWS Setup

1. **SSO Configuration** (Recommended):
   - Open ShotDropper Settings → AWS
   - Enter your SSO Start URL (e.g., `https://your-org.awsapps.com/start`)
   - Enter SSO Region, Account ID, and Role Name
   - Click "Sign In" to authenticate via browser

2. **AWS Profile** (Alternative):
   - Configure AWS CLI: `aws configure sso`
   - Set profile name in ShotDropper Settings
   - Credentials are loaded automatically

### Workflow Configuration

Workflows define how filenames are parsed and where files are uploaded.

#### Path Template

Define your S3 path structure using placeholders:

```
CLIENTS/{CLIENT}/SHOWS/{SHOW}/shots/{SHOT}/vfx/
```

Placeholders are wrapped in `{}` and will be replaced with extracted values.

#### Extraction Rules

Define regex patterns to extract values from filenames:

```json
{
  "name": "VFX Shot Pattern",
  "pattern": "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z]+)",
  "captureGroupMappings": [
    {"groupIndex": 1, "placeholderName": "SHOW"},
    {"groupIndex": 2, "placeholderName": "episode"},
    {"groupIndex": 3, "placeholderName": "shot"},
    {"groupIndex": 4, "placeholderName": "category"}
  ]
}
```

For filename `MyShow_102_0010_comp.nk`:
- Group 1 → SHOW = "MyShow"
- Group 2 → episode = "102"
- Group 3 → shot = "0010"
- Group 4 → category = "comp"

#### Transformations

Apply transformations to extracted values:

- `UPPERCASE` - Convert to uppercase
- `lowercase` - Convert to lowercase
- `Capitalize` - Capitalize first letters
- `Pad Left (zeros)` - Pad with leading zeros

### Sample Workflow

See `Examples/vfx_workflow.json` for a complete workflow configuration.

## Usage

### GUI App

1. **Launch ShotDropper** - appears in menu bar
2. **Sign in to AWS** - click menu bar icon → Sign In
3. **Select Workflow** - choose or create a workflow
4. **Drop Files** - drag files/folders onto drop zone
5. **Confirm & Upload** - review destinations and click Upload

### CLI Tool

```bash
# Check status
shotdrop status

# Upload a file
shotdrop upload /path/to/MyShow_102_0010_comp.nk

# List active uploads
shotdrop list

# Pause/resume uploads
shotdrop pause
shotdrop resume

# View upload history
shotdrop history --limit 20

# Manage workflows
shotdrop config
shotdrop config --set-workflow <workflow-id>

# Run headless server
shotdrop server --port 9847
```

### Automation

Connect to the CLI server for automation:

```bash
# Send commands via netcat
echo '{"command":"status"}' | nc localhost 9847

# Upload via API
echo '{"command":"upload","args":{"path":"/path/to/file.nk"}}' | nc localhost 9847
```

## File Types Supported

| Category | Extensions |
|----------|------------|
| Nuke Comps | `.nk`, `.nknc` |
| Image Sequences | `.exr`, `.tif`, `.tiff`, `.png`, `.dpx` |
| Video | `.mov`, `.mp4`, `.avi`, `.mkv`, `.mxf` |
| Audio | `.wav`, `.aiff`, `.mp3`, `.aac` |
| Project Files | `.aep`, `.prproj`, `.blend`, `.hip`, `.ma`, `.mb` |

## Architecture

```
ShotDropper/
├── Sources/
│   ├── ShotDropperCore/       # Core business logic
│   │   ├── Models/            # Data models
│   │   └── Services/          # AWS, Upload, Extraction services
│   ├── ShotDropperApp/        # SwiftUI macOS app
│   │   └── Views/             # UI components
│   └── ShotDropperCLI/        # Command-line interface
├── Tests/
│   └── ShotDropperTests/      # Unit tests
└── Examples/                  # Sample configurations
```

### Key Components

- **WorkflowConfiguration**: Defines bucket, path template, extraction rules
- **FileExtractionService**: Parses filenames and extracts metadata
- **S3UploadService**: Handles uploads with multipart support
- **UploadManager**: Orchestrates queue and parallel uploads
- **CLIServerService**: TCP server for remote control

## Extending

### Adding Storage Providers

The `StorageProvider` enum supports:
- Amazon S3 (implemented)
- Google Cloud Storage (planned)
- Azure Blob Storage (planned)
- Local/Network paths (planned)

To add a new provider:
1. Add case to `StorageProvider` enum
2. Create upload service implementing same interface
3. Update UI to show provider-specific options

### Custom Extraction Patterns

Create custom extraction rules for any naming convention:

```swift
ExtractionRule(
    name: "Custom Pattern",
    pattern: "YOUR_REGEX_HERE",
    captureGroupMappings: [
        CaptureGroupMapping(groupIndex: 1, placeholderName: "field1"),
        // ...
    ]
)
```

## Troubleshooting

### Common Issues

**"Not authenticated" error**
- Ensure AWS credentials are valid
- Re-authenticate via Settings → AWS → Sign In

**Files not matching pattern**
- Check extraction rule regex
- Verify filename matches expected pattern
- Use test feature in workflow editor

**Upload failures**
- Check S3 bucket permissions
- Verify network connectivity
- Check AWS region matches bucket

### Debug Mode

Enable debug logging in Settings → Advanced → Enable debug logging

Logs are stored in: `~/Library/Application Support/ShotDropper/logs/`

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Support

- [GitHub Issues](https://github.com/your-org/dragndrop/issues)
- [Documentation](https://github.com/your-org/dragndrop/wiki)
