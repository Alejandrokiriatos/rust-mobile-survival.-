# Rust Mobile Survival

Juego original de supervivencia 3D para Android, inspirado en el género sandbox. No usa código, modelos ni texturas propietarios de Rust.

## Estado de esta etapa

- Terreno reconstruido con geometría de mayor resolución (16 sectores, 96 × 96 celdas por sector), relieve multicapa, crestas, costa irregular y color por vértice según altura e inclinación; no depende de una textura geométrica plana.
- Vegetación 3D distribuida por pendiente y zonas ambientales, con instanciación múltiple para reducir llamadas de dibujo.

- Cámara en primera persona y controles táctiles básicos.
- Mundo insular de **512 x 512 metros**.
- Terreno dividido en 16 sectores con colisión independiente.
- Elevaciones, costa y agua generadas proceduralmente.
- Recolección de madera, piedra y fibra con hacha fabricable.
- Joystick analógico táctil, cámara multitáctil, salto y carrera.
- Fabricación de hacha, refugio, fogata y raciones.
- Necesidades de hambre y sed, daño por inanición y fauna hostil básica.
- Ciclo día/noche y guardado local de inventario, estado y construcciones.
- Modelos 3D reales del **Kenney Nature Kit 2.1**, licencia CC0.
- Renderizador Godot Compatibility / OpenGL para móviles.
- Objetivo de rendimiento: 30 FPS; debe medirse en el TECNO BG6.

## Recursos 3D incluidos

El repositorio ya contiene seis modelos GLB originales del Kenney Nature Kit 2.1:

- tree_default.glb y tree_oak.glb
- rock_largeA.glb y rock_smallA.glb
- plant_bush.glb y grass.glb

Son recursos externos reales, no mallas sustitutas creadas por el juego. La licencia CC0 permite su uso y modificación; la atribución no es obligatoria. Fuente oficial: https://kenney.nl/assets/nature-kit. El archivo de licencia y procedencia está en assets/kenney/nature-kit/License.txt.

Para ampliar el repertorio de naturaleza, se puede descargar el paquete completo desde la página oficial y añadir modelos GLB adicionales a esa misma carpeta.

## Abrir y probar

1. Instala Godot 4.x.
2. Descarga o clona este repositorio.
3. Abre project.godot en Godot.
4. Ejecuta la escena principal.

## Validación automática

GitHub Actions descarga Godot 4.4.1, importa los seis modelos GLB, comprueba los scripts y ejecuta la escena principal en modo headless. Esto verifica la carga y el arranque del proyecto; no sustituye una prueba gráfica ni una medición de FPS en el teléfono.

## Rendimiento móvil

El terreno usa 16 sectores de 96 x 96 celdas cada uno (aprox. 295.000 triángulos en total). El relieve combina ruido de varias escalas y crestas de mayor amplitud, la línea costera se deforma para evitar una isla circular perfecta y el material usa color por vértice (playa, pradera, ladera rocosa y zona alta). La cantidad de vegetación, sombras y distancia de dibujado se ajustarán después de medir el rendimiento en el dispositivo.

## Sistemas de supervivencia

La versión actual incluye un ciclo día/noche de 15 minutos, animales hostiles básicos, fabricación inicial, refugio, fogata, comida, bebida en la costa y guardado local mediante `user://rust_mobile_save.cfg`. La distribución de recursos del mundo vuelve a generarse al iniciar una partida; el guardado conserva el estado del jugador y las construcciones.

## Android

La APK se generará después de validar el juego y configurar la exportación Android con plantillas de Godot, JDK y Android SDK.

## Licencias

- Terreno PBR: ambientCG Ground 053, Ground 067, Ground 090 y Rock 063; CC0 1.0. Fuentes: https://ambientcg.com/view?id=Ground053, https://ambientcg.com/view?id=Ground067, https://ambientcg.com/view?id=Ground090, https://ambientcg.com/view?id=Rock063.
- Código del proyecto: MIT.
- Naturaleza 3D: Kenney Nature Kit 2.1, CC0 1.0.
