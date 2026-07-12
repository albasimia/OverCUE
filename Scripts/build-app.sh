#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
APP_DIR="${OUTPUT_DIR}/OverCUE.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_ARGS=(-c release --arch arm64 --arch x86_64)

cd "${ROOT_DIR}"
swift build "${BUILD_ARGS[@]}" --product OverCUE
swift build "${BUILD_ARGS[@]}" --product overcue-cli
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p \
    "${APP_DIR}/Contents/MacOS" \
    "${APP_DIR}/Contents/Helpers" \
    "${APP_DIR}/Contents/Resources"

cp "${ROOT_DIR}/Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_DIR}/OverCUE" "${APP_DIR}/Contents/MacOS/OverCUE"
cp "${BIN_DIR}/overcue-cli" "${APP_DIR}/Contents/Helpers/overcue-cli"
cp "${ROOT_DIR}/Sources/OverCUEApp/Resources/OverCUEIcon.png" \
    "${APP_DIR}/Contents/Resources/OverCUEIcon.png"
cp -R "${BIN_DIR}/OverCUE_OverCUEApp.bundle" \
    "${APP_DIR}/Contents/Resources/OverCUE_OverCUEApp.bundle"
cp -R "${BIN_DIR}/OverCUE_OverCUECore.bundle" \
    "${APP_DIR}/Contents/Resources/OverCUE_OverCUECore.bundle"

chmod 755 \
    "${APP_DIR}/Contents/MacOS/OverCUE" \
    "${APP_DIR}/Contents/Helpers/overcue-cli"

for binary in \
    "${APP_DIR}/Contents/MacOS/OverCUE" \
    "${APP_DIR}/Contents/Helpers/overcue-cli"
do
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " != *" x86_64 "* ]]; then
        echo "Universal Binary verification failed: ${binary} (${architectures})" >&2
        exit 1
    fi
done

codesign --force --sign "${SIGN_IDENTITY}" \
    --identifier "jp.watari.OverCUE.helper" \
    "${APP_DIR}/Contents/Helpers/overcue-cli"
codesign --force --sign "${SIGN_IDENTITY}" \
    --identifier "jp.watari.OverCUE" \
    "${APP_DIR}"

echo "Built Universal Binary ${APP_DIR} (arm64 + x86_64)"
