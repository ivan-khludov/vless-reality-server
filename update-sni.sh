#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
  require_root
  require_reality_config

  local current_sni current_dest dest_port new_sni new_dest tmp_config
  IFS="|" read -r current_sni _ < <(load_reality_settings_from_config)
  current_dest="$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "${XRAY_CONFIG_PATH}")"
  if [[ "${current_dest}" == *:* ]]; then
    dest_port="${current_dest##*:}"
  else
    dest_port="443"
  fi

  read -r -p "SNI (default: ${current_sni}): " new_sni || true
  new_sni="${new_sni:-$current_sni}"
  new_sni="${new_sni//[[:space:]]/}"
  if [[ -z "${new_sni}" ]]; then
    new_sni="${current_sni}"
  fi

  new_dest="${new_sni}:${dest_port}"

  tmp_config="$(mktemp)"
  jq --arg sni "${new_sni}" --arg dest "${new_dest}" \
    '.inbounds[0].streamSettings.realitySettings.serverNames[0] = $sni | .inbounds[0].streamSettings.realitySettings.dest = $dest' \
    "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  apply_config_from_temp "${tmp_config}"

  restart_xray_and_rewrite_clients

  echo ""
  echo "Done. SNI updated to ${new_sni}, Xray restarted, clients file updated."
}

main "$@"
