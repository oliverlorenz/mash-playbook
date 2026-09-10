#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2026 2026 Oliver Lorenz
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Fetches secrets from Bitwarden/Vaultwarden into
# `inventory/host_vars/<hostname>/secrets.yml` -- one `key: value` line per item
# (item name -> variable name, item password field -> value). Counterpart of
# `bin/push_secrets.sh`.
#
# Auth: if BW_CLIENTID, BW_CLIENTSECRET and BW_PASSWORD are set in the
# environment (how CI passes them), log in non-interactively via API key against
# BW_SERVER, in a throwaway data dir that neither touches nor depends on any `bw`
# session already on the machine. Otherwise fall back to the interactive `bw`
# session.
#
# Usage: bin/receive_secrets.sh <folder|collection> <hostname> [hostname...]

MODE="$1"

if [ "$MODE" != "folder" ] && [ "$MODE" != "collection" ] || [ $# -lt 2 ]; then
  echo "Usage: $0 <folder|collection> <hostname> [hostname...]" >&2
  exit 1
fi

shift

if [ -n "${BW_CLIENTID:-}" ] && [ -n "${BW_CLIENTSECRET:-}" ] && [ -n "${BW_PASSWORD:-}" ]; then
  BITWARDENCLI_APPDATA_DIR="$(mktemp -d)"
  export BITWARDENCLI_APPDATA_DIR
  trap 'rm -rf "$BITWARDENCLI_APPDATA_DIR"' EXIT

  # The script has no `set -e` (the interactive path below depends on that), so
  # fail loudly here instead of writing a half-empty secrets file downstream.
  if [ -n "${BW_SERVER:-}" ]; then
    bw config server "$BW_SERVER" > /dev/null || { echo "bw config server failed" >&2; exit 1; }
  fi

  # bw login reads BW_CLIENTID / BW_CLIENTSECRET from the environment.
  bw login --apikey > /dev/null || { echo "bw login --apikey failed" >&2; exit 1; }
  BW_SESSION="$(bw unlock "$BW_PASSWORD" --raw)" || { echo "bw unlock failed" >&2; exit 1; }
  export BW_SESSION
else
  LOGIN_CHECK="$(bw login --check | grep 'You are logged in!')"
  if [ -z "$LOGIN_CHECK" ]; then
    echo ""
  else
    export BW_SESSION=$(bw login --raw)
  fi
fi

JSONATA_FILTER='$map($, function($v) {
    $lowercase($v.name) & ": " & $v.login.password
})'

# Recorded as the first line of every secrets file so `bin/push_secrets.sh` knows
# which Vaultwarden server to push back to. An unset `bw config server` means the
# hosted default, https://bitwarden.com.
VAULTWARDEN_SERVER="$(bw config server 2>/dev/null || true)"
[ -n "$VAULTWARDEN_SERVER" ] || VAULTWARDEN_SERVER="https://bitwarden.com"

echo "Receiving secrets from Vaultwarden server: ${VAULTWARDEN_SERVER}" >&2

for MASH_HOSTNAME in "$@"; do
  ITEM_ID=$(bw get "$MODE" "$MASH_HOSTNAME" | jq -r .id)

  if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
    echo "No Bitwarden ${MODE} found for '${MASH_HOSTNAME}', skipping." >&2
    continue
  fi

  OUTPUT_DIR="inventory/host_vars/${MASH_HOSTNAME}"
  mkdir -p "$OUTPUT_DIR"

  {
    printf '# vaultwarden_server: %s\n' "$VAULTWARDEN_SERVER"
    bw list items --"${MODE}id" "$ITEM_ID" | jfq "$JSONATA_FILTER"
  } > "${OUTPUT_DIR}/secrets.yml"

  # List the variable names that were fetched (names only, never their values),
  # so the run is auditable from the logs.
  KEYS="$(sed -n 's/^\([A-Za-z0-9_.-]\{1,\}\): .*/\1/p' "${OUTPUT_DIR}/secrets.yml")"
  KEY_COUNT="$(printf '%s' "$KEYS" | grep -c . || true)"

  echo "Wrote ${OUTPUT_DIR}/secrets.yml (from ${VAULTWARDEN_SERVER}, ${KEY_COUNT} variable(s)):" >&2
  [ -n "$KEYS" ] && printf '%s\n' "$KEYS" | sed 's/^/  - /' >&2 || true
done
