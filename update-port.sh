#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
  require_root
  require_reality_config

  local current_port input_port new_port tmp_config
  IFS="|" read -r _ current_port < <(load_reality_settings_from_config)

  read -r -p "Listen port for VLESS (default: ${current_port}): " input_port || true
  new_port="$(parse_port "${current_port}" "${input_port}")"

  tmp_config="$(mktemp)"
  jq --argjson port "${new_port}" '.inbounds[0].port = $port' "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  apply_config_from_temp "${tmp_config}"

  restart_xray_and_rewrite_clients

  echo ""
  echo "Done. Port updated to ${new_port}, Xray restarted, clients file updated."
}

main "$@"
