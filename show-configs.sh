#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
  require_root
  require_reality_config

  local count
  count="$(jq -r '.inbounds[0].settings.clients | length' "${XRAY_CONFIG_PATH}")"
  echo "==== $(date -Iseconds) (${count} clients) ===="
  echo ""

  local i uuid sid
  for (( i = 0; i < count; i++ )); do
    uuid="$(jq -r --argjson i "$i" '.inbounds[0].settings.clients[$i].id' "${XRAY_CONFIG_PATH}")"
    sid="$(jq -r --argjson i "$i" '.inbounds[0].streamSettings.realitySettings.shortIds[$i]' "${XRAY_CONFIG_PATH}")"
    echo "$(( i + 1 ))) ${uuid}  shortId: ${sid}"
  done
}

main "$@"
