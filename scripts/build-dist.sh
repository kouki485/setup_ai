#!/usr/bin/env bash
# Build a download-and-unzip package for Mac and Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST_DIR="$ROOT/dist"
STAGING="$DIST_DIR/staging"
NAME="AI-Dev-Setup"
OUT_ZIP="$DIST_DIR/${NAME}.zip"

rm -rf "$STAGING" "$OUT_ZIP"
mkdir -p "$STAGING/$NAME"

cp \
  README_JA.txt \
  Start_Windows.bat \
  Start_Mac.command \
  "$STAGING/$NAME/"
cp -R mac windows "$STAGING/$NAME/"

# Local package uses Start_Windows.bat; no need for the GitHub downloader.
rm -f "$STAGING/$NAME/windows/install.bat"

chmod +x \
  "$STAGING/$NAME/Start_Mac.command" \
  "$STAGING/$NAME/mac/mac-setup.sh" \
  "$STAGING/$NAME/windows/wsl-setup.sh"

# Ensure Windows launcher is CRLF + ASCII.
python3 - "$STAGING/$NAME/Start_Windows.bat" <<'PY'
from pathlib import Path
import sys
bat = Path(sys.argv[1])
text = bat.read_text(encoding="ascii")
text = text.replace("\r\n", "\n").replace("\n", "\r\n")
if any(ord(ch) > 127 for ch in text):
    raise SystemExit("Windows launcher must stay ASCII")
bat.write_bytes(text.encode("ascii"))
PY

(
  cd "$STAGING"
  zip -qry "$OUT_ZIP" "$NAME"
)

rm -rf "$STAGING"
echo "Created: $OUT_ZIP"
ls -lh "$OUT_ZIP"
python3 - <<PY
import zipfile
z = zipfile.ZipFile(r"$OUT_ZIP")
names = [i.filename for i in z.infolist()]
for n in names:
    print(n)
required = [
    "AI-Dev-Setup/Start_Windows.bat",
    "AI-Dev-Setup/Start_Mac.command",
    "AI-Dev-Setup/README_JA.txt",
    "AI-Dev-Setup/mac/mac-setup.sh",
    "AI-Dev-Setup/windows/setup.ps1",
    "AI-Dev-Setup/windows/wsl-setup.sh",
]
missing = [r for r in required if r not in names]
if missing:
    raise SystemExit(f"missing in zip: {missing}")
print("zip content list: OK")
PY
