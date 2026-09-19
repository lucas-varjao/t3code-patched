#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/.local/opt/t3code-patched"
CURRENT="$ROOT/current.AppImage"
CURRENT_RELEASE="$ROOT/current-release"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/t3code-patched"
REMOTE_HOST_FILE="$CONFIG_DIR/remote-host"

export T3CODE_DISABLE_AUTO_UPDATE=1

if [[ ! -x "$CURRENT" ]]; then
  echo "T3 patched AppImage nao encontrado: $CURRENT" >&2
  exit 1
fi

if [[ ! -f "$CURRENT_RELEASE" ]]; then
  echo "current-release nao encontrado." >&2
  exit 1
fi

TAG="$(cat "$CURRENT_RELEASE")"
TARGET="$(readlink -f "$CURRENT")"
MANIFEST="$(dirname "$TARGET")/manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest da release nao encontrado: $MANIFEST" >&2
  exit 1
fi

VERSION="$(
  python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    print(json.load(f)["upstreamVersion"])
PY
)"

REMOTE_HOST="${T3_PATCHED_REMOTE_HOST:-}"

if [[ -z "$REMOTE_HOST" && -r "$REMOTE_HOST_FILE" ]]; then
  REMOTE_HOST="$(head -n 1 "$REMOTE_HOST_FILE")"
fi

desktop_already_running() {
  pgrep -u "$UID" \
    -f '^/tmp/\.mount_[^ ]+/t3code( |$)' \
    >/dev/null 2>&1
}

coordinate_devbox() {
  local status attempt

  if [[ -z "$REMOTE_HOST" ]]; then
    echo "T3 patched: remote-host nao configurado; iniciando Desktop sem coordenacao." >&2
    return 0
  fi

  # Se ja existe um Desktop aberto, nunca alteramos o servidor remoto.
  if desktop_already_running; then
    return 0
  fi

  for attempt in 1 2 3 4 5; do
    set +e

    ssh \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -o ConnectionAttempts=1 \
      "$REMOTE_HOST" \
      bash -s -- "$VERSION" "$TAG" <<'REMOTE'
exec "$HOME/dev/t3code-patched/scripts/activate-devbox.sh" "$1" "$2"
REMOTE

    status=$?

    set -e

    case "$status" in
      0)
        return 0
        ;;
      75)
        # Pode ser apenas o tunnel do Desktop anterior terminando.
        sleep 1
        ;;
      *)
        echo "T3 patched: coordenacao da devbox falhou (status $status)." >&2
        echo "Iniciando o Desktop sem interromper o servidor remoto." >&2
        return 0
        ;;
    esac
  done

  echo "T3 patched: devbox ainda esta em uso; servidor nao foi reiniciado." >&2
  return 0
}

coordinate_devbox

exec "$CURRENT" "$@"
