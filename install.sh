#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

XRAY_INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

detect_ubuntu() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      echo "Warning: not Ubuntu detected. Script was tested on Ubuntu 24.04." >&2
    fi
  else
    echo "Could not detect OS (no /etc/os-release)." >&2
  fi
}

install_dependencies() {
  echo "Installing dependencies (curl, openssl, uuid-runtime, jq)..."
  apt-get update -y
  apt-get install -y curl openssl uuid-runtime jq
}

install_xray() {
  if command -v xray >/dev/null 2>&1 && [[ -x /usr/local/bin/xray ]]; then
    echo "Xray is already installed, skipping installation."
    return
  fi

  echo "Installing Xray via official script..."
  local script_path
  script_path="$(mktemp)"
  curl -LsS "${XRAY_INSTALL_SCRIPT_URL}" -o "${script_path}"
  bash "${script_path}" install -u root
  rm -f "${script_path}"
}

# Returns "uuid|private_key|public_key|short_id" on stdout. Messages go to stderr.
generate_keys() {
  echo "Generating UUID, X25519 keys and short id..." >&2
  local uuid private public short key_output
  uuid="$(uuidgen)"
  key_output="$(cd /tmp && /usr/local/bin/xray x25519 2>&1)" || true
  private="$(echo "${key_output}" | grep -i 'PrivateKey' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r')" || true
  public="$(echo "${key_output}" | grep -i 'Password' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r')" || true
  if [[ -z "${private}" || -z "${public}" ]]; then
    echo "Error generating X25519 keys. xray x25519 output:" >&2
    echo "${key_output}" >&2
    exit 1
  fi
  short="$(openssl rand -hex 4)"
  echo "UUID: ${uuid}" >&2
  echo "Public key: ${public}" >&2
  echo "Short ID: ${short}" >&2
  echo "${uuid}|${private}|${public}|${short}"
}

# Arguments: uuid private_key port dest sni short_id public_key client_name
write_config() {
  local uuid="$1"
  local private="$2"
  local port="$3"
  local dest="$4"
  local sni="$5"
  local short_id="$6"
  local public_key="$7"
  local client_name="$8"

  echo "Creating Xray config (VLESS+Reality) at ${XRAY_CONFIG_PATH}..." >&2
  mkdir -p "$(dirname "${XRAY_CONFIG_PATH}")"

  jq -n \
    --arg uuid "${uuid}" \
    --arg private "${private}" \
    --argjson port "${port}" \
    --arg dest "${dest}" \
    --arg sni "${sni}" \
    --arg short_id "${short_id}" \
    --arg client_name "${client_name}" \
    '{
      log: { loglevel: "warning" },
      inbounds: [{
        port: $port,
        protocol: "vless",
        settings: {
          clients: [{ id: $uuid, flow: "xtls-rprx-vision", email: $client_name }],
          decryption: "none"
        },
        streamSettings: {
          network: "tcp",
          security: "reality",
          realitySettings: {
            show: false,
            dest: $dest,
            xver: 0,
            serverNames: [$sni],
            privateKey: $private,
            shortIds: [$short_id]
          }
        }
      }],
      outbounds: [
        { protocol: "freedom", tag: "direct" },
        { protocol: "blackhole", tag: "blocked" }
      ]
    }' > "${XRAY_CONFIG_PATH}"
  ensure_xray_config_readable

  mkdir -p "$(dirname "${SERVER_PUBLIC_KEY_FILE}")"
  echo "${public_key}" > "${SERVER_PUBLIC_KEY_FILE}"
  chmod 600 "${SERVER_PUBLIC_KEY_FILE}"
}

main() {
  require_root
  detect_ubuntu

  # Prompt for SNI and listen port (first install only)
  local input_sni input_port sni port dest_for_config
  # ---- SNI ----
  read -r -p "SNI (default: ${DEFAULT_SNI}): " input_sni || true
  if [[ -z "${input_sni//[[:space:]]/}" ]]; then
    sni="${DEFAULT_SNI}"
  else
    sni="${input_sni}"
  fi
  # ---- Listen port (inbound on this server) ----
  read -r -p "Listen port for VLESS (default: ${DEFAULT_PORT}): " input_port || true
  port="$(parse_port "${DEFAULT_PORT}" "${input_port}")"
  # ---- Reality dest: upstream is always HTTPS, so port 443 ----
  dest_for_config="${sni}:443"

  local client_name
  read -r -p "Client name (default: ${DEFAULT_CLIENT_NAME}): " client_name || true
  client_name="${client_name:-$DEFAULT_CLIENT_NAME}"

  install_dependencies
  install_xray

  local uuid_value private_key public_key short_id
  IFS="|" read -r uuid_value private_key public_key short_id < <(generate_keys)
  write_config "$uuid_value" "$private_key" "$port" "$dest_for_config" "$sni" "$short_id" "$public_key" "$client_name"
  restart_xray
  build_client_link "$uuid_value" "$short_id" "$public_key" "$port" "$sni" "$client_name"

  echo ""
  echo "Done. Xray with VLESS+Reality is running on port ${port}."
}

main "$@"
