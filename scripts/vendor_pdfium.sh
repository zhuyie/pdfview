#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/3rdparty/pdfium"
DOWNLOAD_DIR="${VENDOR_DIR}/downloads"

# shellcheck disable=SC1091
source "${VENDOR_DIR}/vendor.env"

MAC_ARCHIVE="pdfium-mac-univ.tgz"
WIN_ARCHIVE="pdfium-win-x64.tgz"
BASE_URL="https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_RELEASE_ASSET_TAG}"

mkdir -p "${DOWNLOAD_DIR}"

download() {
  local archive_name="$1"
  local output_path="${DOWNLOAD_DIR}/${archive_name}"
  curl -L --fail --output "${output_path}" "${BASE_URL}/${archive_name}"
}

verify_archive() {
  local archive_name="$1"
  local expected_sha
  expected_sha="$(awk "/ ${archive_name}\$/ { print \\\$1 }" "${VENDOR_DIR}/SHA256SUMS")"
  local actual_sha
  actual_sha="$(shasum -a 256 "${DOWNLOAD_DIR}/${archive_name}" | awk '{ print $1 }')"
  if [[ "${actual_sha}" != "${expected_sha}" ]]; then
    echo "SHA256 mismatch for ${archive_name}" >&2
    echo "expected: ${expected_sha}" >&2
    echo "actual:   ${actual_sha}" >&2
    exit 1
  fi
}

extract_archive() {
  local archive_name="$1"
  local output_dir="$2"
  rm -rf "${output_dir}"
  mkdir -p "${output_dir}"
  tar -xzf "${DOWNLOAD_DIR}/${archive_name}" -C "${output_dir}"
}

download "${MAC_ARCHIVE}"
download "${WIN_ARCHIVE}"

verify_archive "${MAC_ARCHIVE}"
verify_archive "${WIN_ARCHIVE}"

extract_archive "${MAC_ARCHIVE}" "${VENDOR_DIR}/mac-univ"
extract_archive "${WIN_ARCHIVE}" "${VENDOR_DIR}/win-x64"

echo "Vendored PDFium ${PDFIUM_VERSION} into ${VENDOR_DIR}"
