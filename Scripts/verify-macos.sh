#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="${ROOT_DIR}/dist/OverCUE.app"
MODULE_CACHE_DIR="${ROOT_DIR}/.build/overcue-module-cache"
BINARIES=(
    "${APP_DIR}/Contents/MacOS/OverCUE"
    "${APP_DIR}/Contents/Helpers/overcue-cli"
)

cd "${ROOT_DIR}"
mkdir -p "${MODULE_CACHE_DIR}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}"
export SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIR}"

echo "==> Debug build"
swift build --disable-sandbox

echo "==> Core checks"
swift run --disable-sandbox overcue-checks

echo "==> Release Universal Binary app build"
"${ROOT_DIR}/Scripts/build-app.sh"

echo "==> Universal Binary verification"
for binary in "${BINARIES[@]}"; do
    architectures="$(lipo -archs "${binary}")"
    [[ " ${architectures} " == *" arm64 "* && " ${architectures} " == *" x86_64 "* ]]
    echo "${binary}: ${architectures}"
done

echo "==> Code-signature verification"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
codesign -dv --verbose=2 "${APP_DIR}" 2>&1 | grep '^Signature='

echo "macOS verification passed: ${APP_DIR}"
