#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
TAG="${2:-}"

T3_HOME="${T3CODE_HOME:-$HOME/.t3}"
VERSIONS="$T3_HOME/runtime/versions"
TARGET="$VERSIONS/$VERSION"
RUNTIME_STATE="$T3_HOME/userdata/server-runtime.json"

if [[ -z "$VERSION" || -z "$TAG" ]]; then
  echo "Uso: $0 <version> <patched-tag>" >&2
  exit 2
fi

echo "=== T3 PATCHED DEVBOX ACTIVATION ==="
echo "Target: $TAG"

if [[ ! -x "$TARGET/t3" ]]; then
  echo "Runtime $VERSION nao esta instalado." >&2
  exit 1
fi

if [[ ! -f "$TARGET/.install-complete" \
   || "$(cat "$TARGET/.install-complete")" != "$VERSION" ]]
then
  echo "Runtime $VERSION nao esta completo." >&2
  exit 1
fi

if [[ ! -f "$TARGET/.patched-release" \
   || "$(cat "$TARGET/.patched-release")" != "$TAG" ]]
then
  echo "Runtime $VERSION nao corresponde a $TAG." >&2
  exit 1
fi

ACTUAL_VERSION="$("$TARGET/t3" --version)"

if [[ "$ACTUAL_VERSION" != "t3 v$VERSION" ]]; then
  echo "Versao inesperada: $ACTUAL_VERSION" >&2
  exit 1
fi

if [[ ! -s "$RUNTIME_STATE" ]]; then
  echo "READY: nenhum servidor T3 esta registrado."
  exit 0
fi

read -r PID PORT < <(
  python3 - "$RUNTIME_STATE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        state = json.load(f)

    pid = int(state["pid"])
    port = int(state["port"])

    if pid > 0 and 0 < port < 65536:
        print(pid, port)
except Exception:
    pass
PY
)

if [[ -z "${PID:-}" || -z "${PORT:-}" ]]; then
  echo "READY: server-runtime.json nao contem um processo valido."
  exit 0
fi

if ! kill -0 "$PID" 2>/dev/null; then
  echo "READY: o servidor registrado nao esta mais em execucao."
  exit 0
fi

RUNNING_EXE="$(readlink -f "/proc/$PID/exe" 2>/dev/null || true)"

if [[ "$RUNNING_EXE" == "$TARGET/t3" ]]; then
  echo "UP TO DATE: servidor ja esta executando $TAG"
  exit 0
fi

case "$RUNNING_EXE" in
  "$VERSIONS"/*/t3)
    ;;
  *)
    echo "Recusando encerrar PID $PID: executavel inesperado:" >&2
    echo "  ${RUNNING_EXE:-desconhecido}" >&2
    exit 1
    ;;
esac

mapfile -d '' -t CMDLINE < "/proc/$PID/cmdline" 2>/dev/null || true

if [[ "${CMDLINE[1]:-}" != "serve" ]]; then
  echo "Recusando encerrar PID $PID: nao parece ser 't3 serve'." >&2
  exit 1
fi

connection_count() {
  local count

  count="$(
    ss -Htn state established "( sport = :$PORT )" 2>/dev/null \
      | grep -c . \
      || true
  )"

  printf '%s\n' "${count:-0}"
}

CONNECTIONS="$(connection_count)"

if (( CONNECTIONS > 0 )); then
  echo "DEFERRED: servidor ainda possui $CONNECTIONS conexao(oes) ativa(s)."
  echo "PID: $PID"
  echo "Runtime atual: $RUNNING_EXE"
  echo "Nenhum processo foi interrompido."
  exit 75
fi

# Evita uma corrida com um cliente que esteja se reconectando.
sleep 1

CONNECTIONS="$(connection_count)"

if (( CONNECTIONS > 0 )); then
  echo "DEFERRED: uma conexao apareceu antes da troca."
  echo "Nenhum processo foi interrompido."
  exit 75
fi

echo "Parando servidor antigo PID $PID..."
kill -TERM "$PID"

for _ in {1..50}; do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi

  sleep 0.1
done

if kill -0 "$PID" 2>/dev/null; then
  echo "Servidor PID $PID nao encerrou apos SIGTERM." >&2
  exit 1
fi

echo "READY: servidor antigo encerrado."
echo "O Desktop iniciara $TAG usando o runtime patched pre-instalado."
