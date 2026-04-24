#!/bin/bash
set -e
cd "$(dirname "$0")"

# Rebuild the icon if the source SVG is newer than the bundled .icns
if [ icon/icon.svg -nt MyCommander.app/Contents/Resources/MyCommander.icns ]; then
    echo "Regenerating app icon..."
    swift icon/make_icns.swift
    cp -f icon/MyCommander.icns MyCommander.app/Contents/Resources/MyCommander.icns
    touch MyCommander.app
fi

swift build -c release
cp -f .build/release/MyCommander MyCommander.app/Contents/MacOS/MyCommander
open MyCommander.app
