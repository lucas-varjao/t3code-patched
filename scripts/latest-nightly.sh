#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
import re
import urllib.request

url = "https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100"

headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "t3code-patched",
}

token = os.environ.get("GITHUB_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"

request = urllib.request.Request(url, headers=headers)

with urllib.request.urlopen(request, timeout=30) as response:
    releases = json.load(response)

pattern = re.compile(
    r"^v[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[0-9]+$"
)

nightlies = [
    release
    for release in releases
    if release.get("prerelease")
    and pattern.fullmatch(release.get("tag_name", ""))
    and release.get("published_at")
]

if not nightlies:
    raise SystemExit("Nenhuma nightly publicada encontrada.")

nightlies.sort(key=lambda release: release["published_at"])
latest = nightlies[-1]

print(latest["tag_name"])
PY
