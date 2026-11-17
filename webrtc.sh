#!/bin/sh
# Install the WebRTC extension of the native game (addons/webrtc_native, not
# in git: ~90 MB for every platform). The web build has WebRTC built in.
set -e
cd "$(dirname "$0")"
VERSION=1.2.2-stable
SHA256=98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5
[ -f addons/webrtc_native/webrtc_native.gdextension ] && exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/webrtc.zip" \
	"https://github.com/godotengine/webrtc-native/releases/download/$VERSION/godot-extension-webrtc_native.zip"
echo "$SHA256  $tmp/webrtc.zip" | sha256sum -c - >/dev/null
unzip -qo "$tmp/webrtc.zip" 'addons/webrtc_native/*' -d .
echo "WebRTC extension installed in addons/webrtc_native"
