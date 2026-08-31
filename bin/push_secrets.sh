#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2026 Oliver Lorenz
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Pushes the secrets from `inventory/host_vars/<hostname>/secrets.yml` back into
# Bitwarden/Vaultwarden. It is the counterpart of `bin/receive_secrets.sh`.
#
# For every `key: value` entry in the secrets file:
#   - if a matching Bitwarden item already holds the same password  -> skipped silently
#   - if a matching item exists but the password differs            -> asks before updating
#   - if no matching item exists                                    -> asks before creating
#
# Item names are matched case-insensitively against the local key, mirroring the
# `$lowercase($v.name)` transform done by `bin/receive_secrets.sh`.
#
# Usage: bin/push_secrets.sh <folder|collection> <hostname> [hostname...]

set -eu

MODE="${1:-}"

if [ "$MODE" != "folder" ] && [ "$MODE" != "collection" ] || [ $# -lt 2 ]; then
  echo "Usage: $0 <folder|collection> <hostname> [hostname...]" >&2
  exit 1
fi

shift

for BIN in bw jq; do
  if ! command -v "$BIN" >/dev/null 2>&1; then
    echo "Error: required command '$BIN' not found in PATH." >&2
    exit 1
  fi
done

# --- Bitwarden session -------------------------------------------------------

if ! bw login --check >/dev/null 2>&1; then
  BW_SESSION="$(bw login --raw)"
  export BW_SESSION
fi

if [ "$(bw status | jq -r '.status')" != "unlocked" ]; then
  BW_SESSION="$(bw unlock --raw)"
  export BW_SESSION
fi

echo "Syncing Bitwarden vault..." >&2
bw sync >/dev/null

# --- helpers ---------------------------------------------------------------

# Ask a yes/no question on the controlling terminal. Returns 0 for yes.
confirm() {
  prompt="$1"
  printf '%s [y/N] ' "$prompt" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

created=0
updated=0
skipped=0
unchanged_confirmed=0

for MASH_HOSTNAME in "$@"; do
  SECRETS_FILE="inventory/host_vars/${MASH_HOSTNAME}/secrets.yml"

  if [ ! -f "$SECRETS_FILE" ]; then
    echo "No secrets file at '${SECRETS_FILE}', skipping." >&2
    continue
  fi

  CONTAINER_JSON="$(bw get "$MODE" "$MASH_HOSTNAME" 2>/dev/null || true)"
  CONTAINER_ID="$(printf '%s' "$CONTAINER_JSON" | jq -r '.id // empty')"

  if [ -z "$CONTAINER_ID" ]; then
    echo "No Bitwarden ${MODE} found for '${MASH_HOSTNAME}', skipping." >&2
    continue
  fi

  ORG_ID=""
  if [ "$MODE" = "collection" ]; then
    ORG_ID="$(printf '%s' "$CONTAINER_JSON" | jq -r '.organizationId // empty')"
    if [ -z "$ORG_ID" ]; then
      echo "Collection '${MASH_HOSTNAME}' has no organizationId, skipping." >&2
      continue
    fi
  fi

  ITEMS_JSON="$(bw list items --"${MODE}id" "$CONTAINER_ID")"

  echo ""
  echo "== ${MASH_HOSTNAME} (${MODE}) =="

  # Read `key: value` lines, ignoring comments and blanks. Split on the first ": ".
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
    esac
    case "$line" in
      *': '*) ;;
      *) continue ;;
    esac

    key="${line%%: *}"
    value="${line#*: }"

    # Trim surrounding whitespace from the key.
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$key" ] || continue

    match="$(printf '%s' "$ITEMS_JSON" | jq -c \
      --arg n "$key" \
      'map(select((.name | ascii_downcase) == ($n | ascii_downcase))) | .[0] // empty')"

    if [ -z "$match" ]; then
      if confirm "CREATE  '${key}'?"; then
        if [ "$MODE" = "folder" ]; then
          new_item="$(jq -n --arg name "$key" --arg pw "$value" --arg fid "$CONTAINER_ID" \
            '{type: 1, name: $name, folderId: $fid, notes: null, favorite: false,
              login: {uris: [], username: null, password: $pw, totp: null}, reprompt: 0}')"
          printf '%s' "$new_item" | bw encode | bw create item >/dev/null
        else
          new_item="$(jq -n --arg name "$key" --arg pw "$value" --arg cid "$CONTAINER_ID" --arg oid "$ORG_ID" \
            '{type: 1, name: $name, organizationId: $oid, collectionIds: [$cid], notes: null, favorite: false,
              login: {uris: [], username: null, password: $pw, totp: null}, reprompt: 0}')"
          printf '%s' "$new_item" | bw encode | bw create item --organizationid "$ORG_ID" >/dev/null
        fi
        echo "  created '${key}'"
        created=$((created + 1))
      else
        echo "  skipped creating '${key}'"
        skipped=$((skipped + 1))
      fi
      continue
    fi

    item_id="$(printf '%s' "$match" | jq -r '.id')"
    current_pw="$(printf '%s' "$match" | jq -r '.login.password // ""')"

    if [ "$current_pw" = "$value" ]; then
      # Unchanged - skip silently.
      unchanged_confirmed=$((unchanged_confirmed + 1))
      continue
    fi

    if confirm "UPDATE  '${key}' (value differs)?"; then
      updated_item="$(printf '%s' "$match" | jq --arg pw "$value" '.login.password = $pw')"
      printf '%s' "$updated_item" | bw encode | bw edit item "$item_id" >/dev/null
      echo "  updated '${key}'"
      updated=$((updated + 1))
    else
      echo "  skipped updating '${key}'"
      skipped=$((skipped + 1))
    fi
  done < "$SECRETS_FILE"
done

echo ""
echo "Done. created=${created} updated=${updated} skipped=${skipped} unchanged=${unchanged_confirmed}"
