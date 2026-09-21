#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT/patches/cursor-ask-question.patch"
ASYNC_PATCH="$ROOT/patches/cursor-ask-question-async.patch"
PATCH_REVISION="${PATCH_REVISION:-2}"
WORK_ROOT="$ROOT/.work"
SOURCE="$WORK_ROOT/t3code"
UPSTREAM="https://github.com/pingdotgg/t3code.git"

if [[ ! -f "$PATCH" ]]; then
  echo "Patch não encontrado: $PATCH" >&2
  exit 1
fi

if [[ ! -f "$ASYNC_PATCH" ]]; then
  echo "Patch não encontrado: $ASYNC_PATCH" >&2
  exit 1
fi

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  TAG="$("$ROOT/scripts/latest-nightly.sh")"
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[0-9]+$ ]]; then
  echo "Tag nightly inválida: $TAG" >&2
  exit 1
fi

mkdir -p "$WORK_ROOT"

if [[ ! -d "$SOURCE/.git" ]]; then
  echo "Clonando upstream..."
  git clone \
    --filter=blob:none \
    --no-checkout \
    "$UPSTREAM" \
    "$SOURCE"
fi

echo "Buscando $TAG..."
git -C "$SOURCE" fetch \
  --force \
  origin \
  "refs/tags/$TAG:refs/tags/$TAG"

echo "Preparando checkout limpo..."
git -C "$SOURCE" reset --hard >/dev/null 2>&1 || true
git -C "$SOURCE" clean -fdx >/dev/null
git -C "$SOURCE" checkout --detach "$TAG" >/dev/null

echo "Validando patch..."
git -C "$SOURCE" apply --check "$PATCH"

echo "Aplicando patch base..."
git -C "$SOURCE" apply "$PATCH"

echo "Validando patch assíncrono..."
git -C "$SOURCE" apply --check "$ASYNC_PATCH"

echo "Aplicando patch assíncrono..."
git -C "$SOURCE" apply "$ASYNC_PATCH"

UPSTREAM_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
VERSION="${TAG#v}"

cat > "$WORK_ROOT/manifest.json" <<EOF2
{
  "upstreamVersion": "$VERSION",
  "upstreamTag": "$TAG",
  "upstreamCommit": "$UPSTREAM_SHA",
  "patchRevision": $PATCH_REVISION
}
EOF2

echo
echo "PREPARE: OK"
echo "Version:  $VERSION"
echo "Tag:      $TAG"
echo "Commit:   $UPSTREAM_SHA"
echo "Source:   $SOURCE"
echo "Manifest: $WORK_ROOT/manifest.json"
