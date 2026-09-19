#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/.work/t3code"
MANIFEST="$ROOT/.work/manifest.json"
ARTIFACTS="$ROOT/artifacts"

if [[ ! -d "$SOURCE/.git" || ! -f "$MANIFEST" ]]; then
  echo "Execute scripts/prepare-upstream.sh primeiro." >&2
  exit 1
fi

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upstreamVersion"])' "$MANIFEST")"

echo "=== BUILD T3 PATCHED ==="
echo "Version: $VERSION"
echo "Source:  $SOURCE"

cd "$SOURCE"

# Os valores públicos oficiais usados pelos source builds.
cp .env.example .env

echo
echo "=== DEPENDENCIAS ==="
npx -y pnpm@11.10.0 install --frozen-lockfile

echo
echo "=== TESTES DO PATCH ==="
npx -y pnpm@11.10.0 --filter t3 exec vp test run \
  src/provider/RuntimeInstructions.test.ts \
  src/provider/Layers/CursorAdapter.test.ts

echo
echo "=== TYPECHECK SERVER ==="
npx -y pnpm@11.10.0 --filter t3 typecheck

echo
echo "=== ALINHANDO VERSAO ==="
node scripts/update-release-package-versions.ts "$VERSION"

echo
echo "=== BUILD JS ==="
npx -y pnpm@11.10.0 exec vp run build:desktop

echo
echo "=== BUILD DESKTOP APPIMAGE ==="
rm -rf release
node scripts/build-desktop-artifact.ts \
  --platform linux \
  --target AppImage \
  --arch x64 \
  --build-version "$VERSION" \
  --skip-build \
  --output-dir release \
  --verbose

echo
echo "=== BUILD CLI EXECUTAVEL ==="

# build-exe requer Node >= 25.7; usamos exatamente a versão do release upstream.
if ! command -v nvm >/dev/null 2>&1; then
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.nvm/nvm.sh"
  fi
fi

if ! command -v nvm >/dev/null 2>&1; then
  echo "nvm não encontrado." >&2
  exit 1
fi

CURRENT_NODE="$(node --version)"

nvm install 26.8.2
nvm use 26.8.2

node apps/server/scripts/cli.ts build-exe --verbose

echo
echo "=== RESOURCE MONITOR ==="
cargo build \
  --locked \
  --release \
  --manifest-path native/resource-monitor/Cargo.toml

rm -rf release-cli

node scripts/build-cli-archive.ts \
  --platform linux \
  --arch x64 \
  --version "$VERSION" \
  --resource-monitor-dir native/resource-monitor/target \
  --output-dir release-cli

node scripts/smoke-cli-archive.ts \
  --archive release-cli/* \
  --expect-version "$VERSION"

mkdir -p "$ARTIFACTS"
rm -f "$ARTIFACTS"/*

cp release/*.AppImage "$ARTIFACTS/"
cp release-cli/* "$ARTIFACTS/"
cp "$MANIFEST" "$ARTIFACTS/manifest.json"

(
  cd "$ARTIFACTS"
  sha256sum -- * > SHA256SUMS
)

echo
echo "=== ARTEFATOS ==="
ls -lh "$ARTIFACTS"

echo
echo "BUILD: OK"
