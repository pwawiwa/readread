#!/bin/bash
set -euo pipefail

APP_NAME="Readread"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
RESOURCE_BUNDLE="Readread_Readread.bundle"

echo "Building release executable for ${APP_NAME}..."
swift build -c release

if [ ! -x "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "Error: Built executable not found at ${BUILD_DIR}/${APP_NAME}" >&2
    exit 1
fi

if [ ! -d "${BUILD_DIR}/${RESOURCE_BUNDLE}" ]; then
    echo "Error: Resource bundle not found at ${BUILD_DIR}/${RESOURCE_BUNDLE}" >&2
    exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# SPM's generated Bundle.module accessor resolves Bundle.main.bundleURL/<bundle>
cp -R "${BUILD_DIR}/${RESOURCE_BUNDLE}" "${APP_DIR}/${RESOURCE_BUNDLE}"

cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Readread</string>
    <key>CFBundleIdentifier</key>
    <string>com.readread.app</string>
    <key>CFBundleName</key>
    <string>ReadRead</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Rich Text Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.rtf</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>HTML Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.html</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>EPUB Publication</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.idpf.epub-container</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "Successfully built native macOS application bundle: ${APP_DIR}"
