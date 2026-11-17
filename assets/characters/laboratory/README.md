# Rust Mobile Survival — eight rigged character skins

This folder contains eight generated, rigged GLB character assets.

## Character design

- SKIN_01, SKIN_03, SKIN_05 and SKIN_07: four distinct masculine appearances.
- SKIN_02, SKIN_04, SKIN_06 and SKIN_08: four distinct feminine appearances.
- All four feminine skins wear a fully opaque sports-bra garment and plain survival shorts.
- Feminine hairstyles use long loose hair, a long braid and a ponytail, with two colour/appearance variants of the long style. The preview workflow captures front and rear views to check their full length.
- Masculine hairstyles also vary, including short hair, an afro and a close cut.
- Starter appearance has no armour, backpack, shoes, helmet or extra accessories.
- Hair, clothing, face and body are planned as replaceable customization slots.

The meshes use human anatomy rather than the previous primitive-shape body assembly. Each model includes a game skeleton, facial blend shapes and a curated set of locomotion, swimming, interaction and combat animation clips.

## Dimensions and mobile packaging

The gallery scales every model to the same 1.75 m visual height. Each selectable skin uses the same 0.32 m radius / 1.75 m height collision capsule. Skin choice never changes gameplay attributes.

The build pipeline retains gameplay-relevant animation clips and compacts GLB binary data. It preserves the rig, facial blend shapes, clothing and hair while removing unrelated animation data. See manifest.json for source height, triangle count and final file size.

## Provenance and licence

The models are generated with Ara 3D Gen (MIT-licensed generator code) using MakeHuman core character assets released under CC0 1.0. This repository adds its own opaque sports-bra and plain-shorts garment definitions.

- Generator: https://github.com/olatunde85/3d-gen
- MakeHuman asset licence: https://github.com/makehumancommunity/mpfb2/blob/master/LICENSE.md
- CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/

These are game-ready starting assets, not a claim that final clothing physics, facial animation or all equipment swaps are already implemented. Those systems will be added and tested separately.
