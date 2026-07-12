#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${1:-0.1.0}"
RELEASE_DIR="${ROOT_DIR}/release"
ARCHIVE_NAME="OverCUE-v${VERSION}-macos-universal.zip"
PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "${ROOT_DIR}/Packaging/Info.plist")"

if [[ "${VERSION}" != "${PLIST_VERSION}" ]]; then
    echo "Version mismatch: requested ${VERSION}, Info.plist is ${PLIST_VERSION}" >&2
    exit 1
fi

"${ROOT_DIR}/Scripts/build-app.sh"

codesign --verify --deep --strict "${ROOT_DIR}/dist/OverCUE.app"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

ditto -c -k --sequesterRsrc --keepParent \
    "${ROOT_DIR}/dist/OverCUE.app" \
    "${RELEASE_DIR}/${ARCHIVE_NAME}"

unzip -tq "${RELEASE_DIR}/${ARCHIVE_NAME}"

(
    cd "${RELEASE_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > SHA256SUMS.txt
)

echo "Packaged ${RELEASE_DIR}/${ARCHIVE_NAME}"
echo "Checksum: ${RELEASE_DIR}/SHA256SUMS.txt"
