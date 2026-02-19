# Shared constants and functions for VLESS Reality server scripts.
# Sourced by install.sh, add-config.sh, show-configs.sh, remove-config.sh.
# Caller must set -euo pipefail.

IFS=$'\n\t'

# ===== Constants =====
readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly DEFAULT_PORT=443
readonly DEFAULT_SNI="www.cloudflare.com"
readonly DEFAULT_CLIENT_NAME="auto-vless-reality"

# Data dir: same directory as the script that sourced this file, plus /files
_caller="${BASH_SOURCE[1]:-$BASH_SOURCE[0]}"
_dir="$(cd "$(dirname "${_caller}")" && pwd)"
readonly FILES_DIR="${_dir}/files"
readonly CLIENT_LINKS_FILE="${FILES_DIR}/vless-reality-clients.txt"
readonly SERVER_PUBLIC_KEY_FILE="${FILES_DIR}/.vless-reality-public-key"
readonly SERVER_IP_FILE="${FILES_DIR}/server-ip"

# ===== Helpers =====

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This command must be run as root (or with sudo)." >&2
    exit 1
  fi
}

# Make config readable by the user xray runs as (e.g. nobody). Call after writing XRAY_CONFIG_PATH.
ensure_xray_config_readable() {
  chmod 644 "${XRAY_CONFIG_PATH}"
}

# Move temp config to XRAY_CONFIG_PATH and set permissions. Usage: apply_config_from_temp /path/to/tmp.
apply_config_from_temp() {
  mv "$1" "${XRAY_CONFIG_PATH}"
  ensure_xray_config_readable
}

# Parse port from user input. Usage: port=$(parse_port default_port input_port). Echoes valid port or default.
parse_port() {
  local default="$1"
  local input="${2//[[:space:]]/}"
  if [[ -z "${input}" ]]; then
    echo "${default}"
    return
  fi
  if [[ "${input}" =~ ^[0-9]+$ ]] && [[ "${input}" -ge 1 ]] && [[ "${input}" -le 65535 ]]; then
    echo "${input}"
    return
  fi
  echo "Invalid port, using ${default}." >&2
  echo "${default}"
}

# Exit with error if config does not exist or is not VLESS Reality.
require_reality_config() {
  [[ -f "${XRAY_CONFIG_PATH}" ]] || {
    echo "Config not found: ${XRAY_CONFIG_PATH}. Run install.sh first." >&2
    exit 1
  }
  jq -e '.inbounds[0].streamSettings.security == "reality"' "${XRAY_CONFIG_PATH}" >/dev/null 2>&1 || {
    echo "Config is not VLESS Reality. Run install.sh first." >&2
    exit 1
  }
}

# Returns server external IP on stdout. Uses cached value from SERVER_IP_FILE if present;
# otherwise detects (curl or manual input), writes to file, and echoes. Messages go to stderr.
get_server_ip() {
  local ip
  if [[ -f "${SERVER_IP_FILE}" ]] && [[ -s "${SERVER_IP_FILE}" ]]; then
    ip="$(cat "${SERVER_IP_FILE}")"
    ip="${ip//[[:space:]]/}"
    echo "${ip}"
    return
  fi
  echo "Detecting server external IP..." >&2
  ip="$(curl -4 -s --max-time 5 https://ipv4.icanhazip.com || curl -4 -s --max-time 5 https://ifconfig.me || true)"
  ip="${ip//[[:space:]]/}"
  if [[ -z "${ip}" ]]; then
    echo "Could not detect external IP automatically. Enter it manually:" >&2
    read -r ip
  fi
  mkdir -p "$(dirname "${SERVER_IP_FILE}")"
  echo "${ip}" > "${SERVER_IP_FILE}"
  echo "${ip}"
}

# Returns "sni|port" on stdout (from config).
load_reality_settings_from_config() {
  [[ -f "${XRAY_CONFIG_PATH}" ]] || {
    echo "Config not found: ${XRAY_CONFIG_PATH}. Run install.sh first." >&2
    exit 1
  }
  local sni port
  sni="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "${XRAY_CONFIG_PATH}")"
  port="$(jq -r '.inbounds[0].port' "${XRAY_CONFIG_PATH}")"
  echo "${sni}|${port}"
}

# Build VLESS Reality link for one client.
# Usage: build_client_link_for <uuid> <short_id> <public_key> <ip> <port> <sni> [client_name]
# Output: single line (vless://...)
build_client_link_for() {
  local uuid="$1"
  local short_id="$2"
  local public_key="$3"
  local ip="$4"
  local port="${5:-$DEFAULT_PORT}"
  local sni="${6:-$DEFAULT_SNI}"
  local client_name="${7:-$DEFAULT_CLIENT_NAME}"
  local params
  params="encryption=none"
  params+="&flow=xtls-rprx-vision"
  params+="&security=reality"
  params+="&sni=${sni}"
  params+="&fp=chrome"
  params+="&pbk=${public_key}"
  params+="&sid=${short_id}"
  params+="&type=tcp"
  echo "vless://${uuid}@${ip}:${port}?${params}#${client_name}"
}

# Overwrite CLIENT_LINKS_FILE to match current config (all clients from XRAY_CONFIG_PATH).
# No global mutation: all data from return values and locals.
rewrite_clients_file() {
  local clients_count shortids_count count public_key server_ip sni port
  clients_count="$(jq -r '.inbounds[0].settings.clients | length' "${XRAY_CONFIG_PATH}")"
  shortids_count="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds | length' "${XRAY_CONFIG_PATH}")"
  if [[ "${clients_count}" != "${shortids_count}" ]]; then
    echo "Config corruption detected: clients (${clients_count}) and shortIds (${shortids_count}) count mismatch. Fix config.json manually." >&2
    exit 1
  fi
  count="${clients_count}"
  IFS="|" read -r sni port < <(load_reality_settings_from_config)
  public_key="$(cat "${SERVER_PUBLIC_KEY_FILE}")"
  server_ip="$(get_server_ip)"

  mkdir -p "$(dirname "${CLIENT_LINKS_FILE}")"
  {
    echo "==== $(date -Iseconds) (${count} clients) ===="
    local i uuid sid client_name
    for (( i = 0; i < count; i++ )); do
      uuid="$(jq -r --argjson i "$i" '.inbounds[0].settings.clients[$i].id' "${XRAY_CONFIG_PATH}")"
      sid="$(jq -r --argjson i "$i" '.inbounds[0].streamSettings.realitySettings.shortIds[$i]' "${XRAY_CONFIG_PATH}")"
      client_name="$(jq -r --argjson i "$i" '.inbounds[0].settings.clients[$i].email // empty' "${XRAY_CONFIG_PATH}")"
      client_name="${client_name:-$DEFAULT_CLIENT_NAME}"
      build_client_link_for "$uuid" "$sid" "$public_key" "$server_ip" "$port" "$sni" "$client_name"
    done
  } > "${CLIENT_LINKS_FILE}"

  echo "Clients file updated: ${CLIENT_LINKS_FILE} (${count} clients)."
}

restart_xray() {
  echo "Restarting and enabling Xray service..."
  systemctl daemon-reload || true
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray

  sleep 1
  if ! systemctl is-active --quiet xray; then
    echo "Xray service failed to start. Check logs: journalctl -u xray -e" >&2
    exit 1
  fi
}

restart_xray_and_rewrite_clients() {
  restart_xray
  rewrite_clients_file
}

# Arguments: uuid short_id public_key port sni client_name
# Appends one client link to CLIENT_LINKS_FILE and prints it.
build_client_link() {
  local uuid="$1"
  local short_id="$2"
  local public_key="$3"
  local port="$4"
  local sni="$5"
  local client_name="${6:-$DEFAULT_CLIENT_NAME}"
  local server_ip link

  echo "Building VLESS Reality client link..." >&2
  server_ip="$(get_server_ip)"
  link="$(build_client_link_for "$uuid" "$short_id" "$public_key" "$server_ip" "$port" "$sni" "$client_name")"
  mkdir -p "$(dirname "${CLIENT_LINKS_FILE}")"
  {
    echo "==== $(date -Iseconds) ===="
    echo "${link}"
    echo
  } >> "${CLIENT_LINKS_FILE}"
  echo "Client link saved to file: ${CLIENT_LINKS_FILE}" >&2
  echo "Link:"
  echo "${link}"
}
