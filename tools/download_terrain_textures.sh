#!/usr/bin/env bash
set -euo pipefail
DEST="assets/terrain/ambientcg"
TMP="/tmp/rust-mobile-terrain-textures"
mkdir -p "$DEST" "$TMP"

download_material() {
  local asset="$1"
  local archive="$TMP/${asset}_1K-JPG.zip"
  local extracted="$TMP/${asset}"
  curl -L --fail --retry 3 "https://ambientcg.com/get?file=${asset}_1K-JPG.zip" -o "$archive"
  mkdir -p "$extracted"
  unzip -oq "$archive" -d "$extracted"
  local color_file
  color_file="$(find "$extracted" -type f -iname "*_Color.jpg" -print -quit)"
  if [ -z "$color_file" ]; then
    echo "No se encontró el mapa Color para ${asset}" >&2
    find "$extracted" -maxdepth 2 -type f -print
    exit 1
  fi
  cp "$color_file" "$DEST/${asset}_Color.jpg"
  test -s "$DEST/${asset}_Color.jpg"
}

download_material "Grass005"
download_material "Ground067"
download_material "Ground090"
download_material "Rock063"

cat > "$DEST/License.txt" <<'EOF'
Terrain PBR textures from ambientCG.
Assets: Grass 005, Ground 067, Ground 090, Rock 063.
License: Creative Commons CC0 1.0 Universal.
Official asset pages:
https://ambientcg.com/view?id=Grass005
https://ambientcg.com/view?id=Ground067
https://ambientcg.com/view?id=Ground090
https://ambientcg.com/view?id=Rock063
Only the 1K-JPG Color map from each PBR archive is included.
EOF
