#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
  require_root

  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <client_number>" >&2
    echo "Example: $0 2" >&2
    echo "Run show-configs.sh to list client numbers." >&2
    exit 1
  fi

  local n="$1"
  if [[ ! "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    echo "Client number must be a positive integer." >&2
    exit 1
  fi

  require_reality_config

  local count
  count="$(jq -r '.inbounds[0].settings.clients | length' "${XRAY_CONFIG_PATH}")"
  if [[ "$n" -gt "$count" ]]; then
    echo "Client number ${n} is out of range (1..${count}). Run show-configs.sh to list clients." >&2
    exit 1
  fi

  local i=$(( n - 1 ))
  local tmp_config
  tmp_config="$(mktemp)"
  jq --argjson i "$i" '
    .inbounds[0] = (
      .inbounds[0]
      | .settings.clients = (.settings.clients | .[0:$i] + .[$i+1:])
      | .streamSettings.realitySettings.shortIds = (.streamSettings.realitySettings.shortIds | .[0:$i] + .[$i+1:])
    )
  ' "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  apply_config_from_temp "${tmp_config}"

  restart_xray_and_rewrite_clients

  echo ""
  echo "Done. Client ${n} removed. Clients file updated."
}

main "$@"
