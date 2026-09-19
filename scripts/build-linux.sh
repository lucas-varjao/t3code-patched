#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/.work/t3code"
MANIFEST="$ROOT/.work/manifest.json"
ARTIFACTS="$ROOT/artifacts"
CLI_RESOURCE_MONITOR="$ROOT/.work/cli-resource-monitor"

if [[ ! -d "$SOURCE/.git" || ! -f "$MANIFEST" ]]; then
  echo "Execute scripts/prepare-upstream.sh primeiro." >&2
  exit 1
fi

if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  echo "nvm nao encontrado em $HOME/.nvm/nvm.sh" >&2
  exit 1
fi

# Todo o monorepo desta nightly espera Node 24.13.x.
# O Node 26.8.2 sera usado somente internamente pelo vp no build do SEA.
source "$HOME/.nvm/nvm.sh"
nvm install 24.13.1
nvm use 24.13.1

VERSION="$(
  python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["upstreamVersion"])' \
    "$MANIFEST"
)"

echo "=== BUILD T3 PATCHED ==="
echo "Version: $VERSION"
echo "Source:  $SOURCE"
echo "Node:    $(node --version)"
echo "npm:     $(npm --version)"

cd "$SOURCE"

# Public config oficial para source builds.
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

# Replica o release upstream: o processo continua em Node 24.13.1,
# mas vp usa Node 26.8.2 para gerar o single executable.
VP_NODE_VERSION=26.8.2 \
  node apps/server/scripts/cli.ts build-exe --verbose

echo
echo "=== RESOURCE MONITOR ==="

cargo build \
  --locked \
  --release \
  --target x86_64-unknown-linux-gnu \
  --manifest-path native/resource-monitor/Cargo.toml

rm -rf "$CLI_RESOURCE_MONITOR"
mkdir -p "$CLI_RESOURCE_MONITOR/linux-x64"

cp \
  native/resource-monitor/target/x86_64-unknown-linux-gnu/release/t3-resource-monitor \
  "$CLI_RESOURCE_MONITOR/linux-x64/t3-resource-monitor"

echo
echo "=== BUILD CLI ARCHIVE ==="

rm -rf release-cli

node scripts/build-cli-archive.ts \
  --platform linux \
  --arch x64 \
  --version "$VERSION" \
  --resource-monitor-dir "$CLI_RESOURCE_MONITOR" \
  --output-dir release-cli

echo
echo "=== SMOKE TEST CLI ==="

node scripts/smoke-cli-archive.ts \
  --archive release-cli/* \
  --expect-version "$VERSION"

echo
echo "=== COLETANDO ARTEFATOS ==="

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
