#!/usr/bin/env bash
# Temiz ortamda Linux release derlemesi alıp dist/ altına x86_64 AppImage üretir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ID="io.github.muratboy.bilge"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -n1)"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
OUT_FILE="$OUT_DIR/bilge-${VERSION}-x86_64.AppImage"
APPIMAGETOOL="${APPIMAGETOOL:-$(command -v appimagetool || true)}"

# Piper Doğal Ses Motoru (rhasspy/piper)
# Sürüm: 2023.11.14-2
# İndirme Adresi: https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz
# SHA-256 Özeti: a50cb45f355b7af1f6d758c1b360717877ba0a398cc8cbe6d2a7a3a26e225992
# Not: Betik internetten indirme yapmaz; ikili önceden PIPER_DIR veya ~/development/piper/piper içine konmalıdır.
PIPER_DIR="${PIPER_DIR:-$HOME/development/piper/piper}"

if [[ -z "$VERSION" ]]; then
  echo "pubspec.yaml sürümü okunamadı." >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter komutu PATH içinde bulunamadı." >&2
  exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake komutu PATH içinde bulunamadı." >&2
  exit 1
fi
if [[ -z "$APPIMAGETOOL" || ! -x "$APPIMAGETOOL" ]]; then
  echo "appimagetool bulunamadı; PATH'e ekleyin veya APPIMAGETOOL=/yol/appimagetool ile verin." >&2
  exit 1
fi
if [[ ! -x "$PIPER_DIR/piper" ]]; then
  echo "Piper ikilisi bulunamadı: $PIPER_DIR/piper" >&2
  echo "Lütfen Piper 2023.11.14-2 sürümünü indirin:" >&2
  echo "  https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz" >&2
  echo "ve $HOME/development/piper/ klasörüne açın (veya PIPER_DIR ortam değişkeni ile yolu belirtin)." >&2
  exit 1
fi

STAGE="/tmp/bilge-linux-derleme"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

rm -rf "$STAGE"
mkdir -p "$STAGE/src" "$STAGE/AppDir" "$OUT_DIR"

cp -a "$ROOT/lib" "$ROOT/assets" "$ROOT/linux" "$ROOT/pubspec.yaml" "$ROOT/pubspec.lock" \
  "$ROOT/analysis_options.yaml" "$ROOT/.metadata" "$STAGE/src/"
rm -rf "$STAGE/src/linux/flutter/ephemeral"

(
  cd "$STAGE/src"
  flutter pub get --enforce-lockfile
  flutter build linux --release
)

BUNDLE="$STAGE/src/build/linux/x64/release/bundle"
APPDIR="$STAGE/AppDir"

mkdir -p \
  "$APPDIR/usr/lib/bilge" \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE/." "$APPDIR/usr/lib/bilge/"
ln -s "../lib/bilge/bilge" "$APPDIR/usr/bin/bilge"

mkdir -p "$APPDIR/usr/lib/bilge/piper"
cp -a "$PIPER_DIR/." "$APPDIR/usr/lib/bilge/piper/"
rm -f "$APPDIR/usr/lib/bilge/piper/espeak-ng"

mkdir -p "$APPDIR/usr/share/doc/bilge"
if [[ -d "$ROOT/linux/packaging/licenses" ]]; then
  cp -a "$ROOT/linux/packaging/licenses/." "$APPDIR/usr/share/doc/bilge/"
fi

install -m 0755 "$ROOT/linux/packaging/AppRun" "$APPDIR/AppRun"
install -m 0644 "$ROOT/linux/packaging/${APP_ID}.desktop" "$APPDIR/${APP_ID}.desktop"
install -m 0644 "$ROOT/linux/packaging/${APP_ID}.desktop" "$APPDIR/usr/share/applications/${APP_ID}.desktop"
install -m 0644 "$ROOT/linux/packaging/${APP_ID}.png" "$APPDIR/${APP_ID}.png"
install -m 0644 "$ROOT/linux/packaging/${APP_ID}.png" "$APPDIR/.DirIcon"
install -m 0644 "$ROOT/linux/packaging/${APP_ID}.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/${APP_ID}.png"

rm -f "$OUT_FILE"
ARCH=x86_64 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUT_FILE"
chmod +x "$OUT_FILE"
echo "Üretildi: $OUT_FILE"
