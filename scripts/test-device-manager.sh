#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$REPO_DIR/Tests/DeviceManager"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blueswitch-device-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Fake only the Bluetooth framework boundaries; compile the real manager unchanged.
for module in CoreBluetooth IOBluetooth; do
  xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name "$module" \
    "$TEST_DIR/$module.swift" -emit-module-path "$BUILD_DIR/$module.swiftmodule" \
    -o "$BUILD_DIR/lib$module.dylib"
done

xcrun swiftc -swift-version 5 -I "$BUILD_DIR" -L "$BUILD_DIR" \
  -lCoreBluetooth -lIOBluetooth -Xlinker -rpath -Xlinker "$BUILD_DIR" \
  "$REPO_DIR/Blue Switch/Model/Entity/Device.swift" \
  "$REPO_DIR/Blue Switch/Logging/Log.swift" \
  "$REPO_DIR/Blue Switch/Manager/DeviceManager.swift" \
  "$TEST_DIR/main.swift" -o "$BUILD_DIR/device-manager-tests"

"$BUILD_DIR/device-manager-tests"
