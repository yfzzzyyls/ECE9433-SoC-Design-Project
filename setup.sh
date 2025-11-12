#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${REPO_ROOT}/third_party"
mkdir -p "${THIRD_PARTY_DIR}"

clone_repo() {
    local name="$1"
    local url="$2"
    local commit="$3"
    local dest="${THIRD_PARTY_DIR}/${name}"

    if [ -d "${dest}/.git" ]; then
        echo "[+] Updating ${name}..."
        git -C "${dest}" fetch --tags origin
    elif [ -d "${dest}" ]; then
        echo "[!] ${dest} exists but is not a git repo. Remove or move it, then re-run."
        exit 1
    else
        echo "[+] Cloning ${name}..."
        git clone "${url}" "${dest}"
    fi

    git -C "${dest}" checkout "${commit}"
}

PICORV32_COMMIT="87c89acc18994c8cf9a2311e871818e87d304568"

clone_repo "picorv32" "https://github.com/YosysHQ/picorv32.git" "${PICORV32_COMMIT}"

echo "[✓] Third-party dependencies are ready in ${THIRD_PARTY_DIR}"
