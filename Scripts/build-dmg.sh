#!/bin/bash

# Build and package DragNDrop as a DMG for distribution
# Usage: ./Scripts/build-dmg.sh [--skip-build]

set -e

# Configuration
APP_NAME="DragNDrop"
BUNDLE_ID="com.dragndrop.app"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
DMG_TEMP="$DIST_DIR/dmg-temp"

# Parse arguments
SKIP_BUILD=false
for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
    esac
done

echo "=== DragNDrop DMG Builder ==="
echo "Version: $VERSION"
echo ""

# Create dist directory
mkdir -p "$DIST_DIR"

# Build if not skipping
if [ "$SKIP_BUILD" = false ]; then
    echo "Building release..."
    swift build --configuration release
else
    echo "Skipping build (--skip-build flag set)"
fi

# Verify build exists
if [ ! -f "$BUILD_DIR/dragndrop-app" ]; then
    echo "Error: Build not found at $BUILD_DIR/dragndrop-app"
    echo "Run without --skip-build flag first"
    exit 1
fi

echo "Creating app bundle..."

# Clean up existing bundle
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/dragndrop-app" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>dragndrop</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

echo "App bundle created at: $APP_BUNDLE"

# Create DMG
echo ""
echo "Creating DMG..."

# Clean up any existing DMG temp folder and file
rm -rf "$DMG_TEMP"
rm -f "$DMG_PATH"

# Create temp folder for DMG contents
mkdir -p "$DMG_TEMP"

# Copy app to temp folder
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Calculate size needed (app size + 10MB buffer)
APP_SIZE=$(du -sm "$APP_BUNDLE" | cut -f1)
DMG_SIZE=$((APP_SIZE + 10))

# Create DMG
echo "Creating DMG image (${DMG_SIZE}MB)..."
hdiutil create -srcfolder "$DMG_TEMP" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${DMG_SIZE}m \
    "$DIST_DIR/temp.dmg"

# Convert to compressed DMG
echo "Compressing DMG..."
hdiutil convert "$DIST_DIR/temp.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# Clean up
rm -f "$DIST_DIR/temp.dmg"
rm -rf "$DMG_TEMP"

# Get final size
FINAL_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "=== Build Complete ==="
echo "DMG: $DMG_PATH ($FINAL_SIZE)"
echo ""
echo "To install:"
echo "  1. Open $DMG_PATH"
echo "  2. Drag $APP_NAME to Applications"
echo ""
