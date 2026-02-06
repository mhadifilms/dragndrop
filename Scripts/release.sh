#!/bin/bash

# Build DMG and create GitHub release
# Usage: ./Scripts/release.sh <version>
# Example: ./Scripts/release.sh 1.0.0

set -e

APP_NAME="dragndrop"

# Check for version argument
if [ -z "$1" ]; then
    echo "Usage: ./Scripts/release.sh <version>"
    echo "Example: ./Scripts/release.sh 1.0.0"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"
DMG_FILE=".build/dist/$APP_NAME-$VERSION.dmg"

echo "=== DragNDrop Release Script ==="
echo "Version: $VERSION"
echo "Tag: $TAG"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

# Build DMG
echo "Building DMG..."
VERSION="$VERSION" ./Scripts/build-dmg.sh

# Verify DMG exists
if [ ! -f "$DMG_FILE" ]; then
    echo "Error: DMG not found at $DMG_FILE"
    exit 1
fi

# Generate checksum
echo "Generating checksum..."
cd .build/dist
shasum -a 256 "$APP_NAME-$VERSION.dmg" > "$APP_NAME-$VERSION.dmg.sha256"
cd ../..

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "$TAG"
        git push origin --delete "$TAG" 2>/dev/null || true
    else
        echo "Aborting"
        exit 1
    fi
fi

# Create and push tag
echo "Creating tag $TAG..."
git tag -a "$TAG" -m "Release $VERSION"
git push origin "$TAG"

# Create GitHub release
echo "Creating GitHub release..."
gh release create "$TAG" \
    --title "$APP_NAME $TAG" \
    --generate-notes \
    ".build/dist/$APP_NAME-$VERSION.dmg" \
    ".build/dist/$APP_NAME-$VERSION.dmg.sha256"

echo ""
echo "=== Release Complete ==="
echo "GitHub Release: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
