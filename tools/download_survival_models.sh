#!/usr/bin/env bash
set -euo pipefail
DEST="assets/kenney/survival-kit"
BASE="https://raw.githubusercontent.com/shorepine/kenney/main/3d/survival"
mkdir -p "$DEST/Textures"
for model in resource-stone.glb tool-axe.glb tool-pickaxe.glb resource-wood.glb campfire-pit.glb; do
  curl -L --fail --retry 3 "$BASE/$model" -o "$DEST/$model"
  test -s "$DEST/$model"
done
curl -L --fail --retry 3 "$BASE/Textures/colormap.png" -o "$DEST/Textures/colormap.png"
cat > "$DEST/License.txt" <<'EOF'
Kenney Survival Kit 2.0
Author: Kenney
License: CC0 1.0 Universal.
Official source: https://kenney.nl/assets/survival-kit
Model files mirrored from the public Kenney CC0 asset tree:
https://github.com/shorepine/kenney/tree/main/3d/survival
The models and texture may be used in personal and commercial projects without attribution.
EOF

# Texturas PBR de terreno CC0 de ambientCG (resolución 1K para Android).
bash tools/download_terrain_textures.sh
