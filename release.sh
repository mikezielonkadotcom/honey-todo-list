#!/bin/bash
set -e

# Usage: ./release.sh <version>
# Builds, packages, and creates a GitHub Release. The app's UpdateManager
# polls /releases/latest on launch and offers in-app auto-update.

if [ -z "$1" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.1.0"
    exit 1
fi

VERSION="$1"
REPO="mikezielonkadotcom/honey-todo-list"
APP_NAME="Honey Todo List"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ZIP_NAME="HoneyTodoList-v$VERSION.zip"
ZIP_FILE="$BUILD_DIR/$ZIP_NAME"

# Bump version in Info.plist (both CFBundleVersion and CFBundleShortVersionString)
sed -i '' "s|<string>[0-9]*\.[0-9]*\.[0-9]*</string>|<string>$VERSION</string>|g" Resources/Info.plist

echo "Building v$VERSION..."
./build.sh

echo "Packaging..."
( cd "$BUILD_DIR" && zip -qr "$ZIP_NAME" "$APP_NAME.app" )
echo "Built: $ZIP_FILE"

if ! command -v gh &> /dev/null; then
    echo "gh CLI not found — install it (brew install gh) or upload manually:"
    echo "  https://github.com/$REPO/releases/new"
    echo "  Tag: v$VERSION   Asset: $ZIP_FILE"
    exit 1
fi

echo "Creating GitHub release v$VERSION..."
gh release create "v$VERSION" "$ZIP_FILE" \
    --repo "$REPO" \
    --title "v$VERSION" \
    --notes "Honey Todo List v$VERSION" \
    --latest

echo "✅ Released: https://github.com/$REPO/releases/tag/v$VERSION"
