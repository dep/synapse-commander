#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="Synapse Commander.app"

# Rebuild the icon if the source SVG is newer than the bundled .icns
if [ icon/icon.svg -nt "$APP/Contents/Resources/SynapseCommander.icns" ]; then
    echo "Regenerating app icon..."
    swift icon/make_icns.swift
    cp -f icon/SynapseCommander.icns "$APP/Contents/Resources/SynapseCommander.icns"
    touch "$APP"
fi

swift build -c release

# Copy binary (Swift target is still "SynapseCommander"; bundle executable is "Synapse Commander")
cp -f .build/release/SynapseCommander "$APP/Contents/MacOS/Synapse Commander"

# Embed Sparkle.framework
BUILD_DIR=".build/arm64-apple-macosx/release"
if [ ! -d "$BUILD_DIR/Sparkle.framework" ]; then
    BUILD_DIR=".build/release"
fi
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$BUILD_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"

# Ensure the binary can find Sparkle at Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Synapse Commander" 2>/dev/null || true

open "$APP"
