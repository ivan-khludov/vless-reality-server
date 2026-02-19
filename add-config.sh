#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
  require_root
  require_reality_config

  if [[ ! -f "${SERVER_PUBLIC_KEY_FILE}" ]]; then
    echo "Public key not found: ${SERVER_PUBLIC_KEY_FILE}. Run install.sh first." >&2
    exit 1
  fi

  local public_key uuid short_id client_name tmp_config sni port
  public_key="$(cat "${SERVER_PUBLIC_KEY_FILE}")"
  uuid="$(uuidgen)"
  short_id="$(openssl rand -hex 4)"

  read -r -p "Client name (default: ${DEFAULT_CLIENT_NAME}): " client_name || true
  client_name="${client_name:-$DEFAULT_CLIENT_NAME}"

  echo "New UUID: ${uuid}" >&2
  echo "New Short ID: ${short_id}" >&2

  tmp_config="$(mktemp)"
  jq --arg uuid "${uuid}" --arg sid "${short_id}" --arg email "${client_name}" \
    '(.inbounds[0].settings.clients + [{id: $uuid, flow: "xtls-rprx-vision", email: $email}]) as $new_clients | (.inbounds[0].streamSettings.realitySettings.shortIds + [$sid]) as $new_shortIds | .inbounds[0] = (.inbounds[0] | .settings.clients = $new_clients | .streamSettings.realitySettings.shortIds = $new_shortIds)' \
    "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  apply_config_from_temp "${tmp_config}"

  restart_xray
  IFS="|" read -r sni port < <(load_reality_settings_from_config)
  build_client_link "$uuid" "$short_id" "$public_key" "$port" "$sni" "$client_name"

  echo "" >&2
  echo "Done. New client added, link appended to ${CLIENT_LINKS_FILE}." >&2
}

main "$@"
