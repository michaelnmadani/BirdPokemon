#!/usr/bin/env bash
# Download the TensorFlow Lite C runtime for iOS (Apache 2.0) into
# Vendor/TensorFlowLiteC.xcframework, which the iOS app links to run BirdNET.
# It's the same binary the official TensorFlowLiteC CocoaPod uses, without
# needing CocoaPods. Too big for git, so builds fetch it.
#
#   scripts/birdnet/fetch-tflite-ios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Vendor"
VERSION="2.17.0"
# From the TensorFlowLiteC 2.17.0 podspec (CocoaPods/Specs); SHA-256 of the archive.
URL="https://dl.google.com/tflite-release/ios/prod/tensorflow/lite/release/ios/release/32/20240729-115310/TensorFlowLiteC/2.17.0/0c10b3543e01f547/TensorFlowLiteC-2.17.0.tar.gz"
SHA="${TFLITE_SHA:-9667b476015f136e5b332ce040e12822c4ac6d5c58947882ddc809cdff0fb99e}"

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [[ -f "$OUT/.tflite-version" && "$(cat "$OUT/.tflite-version")" == "$VERSION" ]]; then
  echo "TensorFlowLiteC $VERSION already present in Vendor/"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT
echo "Downloading TensorFlowLiteC ${VERSION}…"
curl -fsSL "$URL" -o "$TMP/tflite.tar.gz"
ACTUAL="$(sha256 "$TMP/tflite.tar.gz")"
if [[ "$ACTUAL" != "$SHA" ]]; then
  echo "Checksum mismatch: expected $SHA, got $ACTUAL" >&2
  exit 1
fi
echo "sha256 $ACTUAL"

tar -xzf "$TMP/tflite.tar.gz" -C "$TMP"
FRAMEWORK="$(find "$TMP" -type d -name TensorFlowLiteC.xcframework | head -1)"
[[ -n "$FRAMEWORK" ]] || { echo "TensorFlowLiteC.xcframework not found in the download" >&2; exit 1; }
rm -rf "$OUT/TensorFlowLiteC.xcframework"
mkdir -p "$OUT"
cp -R "$FRAMEWORK" "$OUT/"
echo "$VERSION" > "$OUT/.tflite-version"
ls "$OUT/TensorFlowLiteC.xcframework"
file "$OUT"/TensorFlowLiteC.xcframework/ios-arm64/TensorFlowLiteC.framework/TensorFlowLiteC 2>/dev/null || true
echo "TensorFlowLiteC $VERSION ready in Vendor/"
