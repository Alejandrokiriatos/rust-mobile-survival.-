# Rust Mobile Survival

Juego original de supervivencia 3D para Android, inspirado en el género sandbox. No usa código, modelos ni texturas propietarios de Rust.

## Estado de esta etapa

- Cámara en primera persona y controles táctiles básicos.
- Mundo insular de **512 x 512 metros**.
- Terreno dividido en 16 sectores con colisión independiente.
- Elevaciones y costa generadas con ruido procedural.
- Recolección de madera, piedra y fibra.
- Recursos visuales cargados desde el paquete 3D real **Kenney Nature Kit** (CC0).
- Renderizador Godot Compatibility / OpenGL para móviles.
- El objetivo de rendimiento es 30 FPS; solo se podrá confirmar con pruebas reales en el TECNO BG6.

## Paquete 3D externo obligatorio

Descarga gratis el **Kenney Nature Kit** desde su página oficial:

https://kenney.nl/assets/nature-kit

Licencia: CC0 1.0. Se permite modificarlo y usarlo incluso en proyectos comerciales. La atribución no es obligatoria.

Descomprime el ZIP y copia el contenido de la carpeta "Models/GLTF format/" en:

assets/kenney/nature-kit/

Conserva también el License.txt original dentro de esa carpeta. El juego busca estos modelos reales del paquete:

- tree_default.glb
- tree_oak.glb
- rock_largeA.glb
- rock_smallA.glb
- plant_bush.glb
- plant_bushLarge.glb

No se generan árboles, piedras ni arbustos geométricos de sustitución. Si falta el paquete, el proyecto muestra un aviso y deja desactivada la distribución de recursos 3D.

## Abrir y probar

1. Instala Godot 4.x.
2. Descarga/clona el repositorio.
3. Instala Kenney Nature Kit siguiendo las instrucciones anteriores.
4. Abre project.godot en Godot.
5. Ejecuta la escena principal.

## Rendimiento móvil

El terreno usa 16 sectores de 64 x 64 celdas cada uno (aprox. 131.000 triángulos en total). La densidad, cantidad de vegetación, sombras y distancia de dibujado se ajustarán después de medir el rendimiento en el teléfono.

## Android

La APK se generará después de terminar el bloque de código y superar la validación de la escena en Godot. La exportación requiere plantillas de Godot, JDK y Android SDK.

## Licencias

- Código del proyecto: MIT.
- Naturaleza 3D: Kenney Nature Kit, CC0 1.0. Página oficial: https://kenney.nl/assets/nature-kit
