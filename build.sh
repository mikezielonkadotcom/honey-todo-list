#!/bin/bash
set -e

APP="HoneyTodoList"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/Honey Todo List.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

swiftc \
  Sources/main.swift \
  Sources/DockManager.swift \
  Sources/StatusBarController.swift \
  Sources/PreferencesWindow.swift \
  Sources/TasksWindow.swift \
  Sources/TasksView.swift \
  Sources/TaskStore.swift \
  Sources/ClickUpAPI.swift \
  Sources/KeychainStore.swift \
  -o "$APP_BUNDLE/Contents/MacOS/$APP" \
  -framework AppKit \
  -framework SwiftUI \
  -target arm64-apple-macosx14.0 \
  -swift-version 6

cp Resources/Info.plist "$APP_BUNDLE/Contents/"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Built: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
echo ""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
