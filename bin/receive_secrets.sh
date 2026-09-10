#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2026 2026 Oliver Lorenz
#
# SPDX-License-Identifier: AGPL-3.0-or-later

MODE="$1"

if [ "$MODE" != "folder" ] && [ "$MODE" != "collection" ] || [ $# -lt 2 ]; then
  echo "Usage: $0 <folder|collection> <hostname> [hostname...]" >&2
  exit 1
fi

shift

LOGIN_CHECK="$(bw login --check | grep 'You are logged in!')"
if [ -z "$LOGIN_CHECK" ]; then
  echo ""
else
  export BW_SESSION=$(bw login --raw)
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
