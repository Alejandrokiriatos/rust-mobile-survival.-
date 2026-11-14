# Rust Mobile Survival

Proyecto original de supervivencia 3D para Android, inspirado en el género de supervivencia sandbox. No utiliza código ni recursos propietarios de Rust.

## Dirección
- Estilo visual: stylized / low-poly.
- Cámara: primera persona.
- Primera entrega: un jugador offline.
- Arquitectura preparada para añadir multijugador más adelante.
- Objetivo inicial: 30 FPS en móviles modestos (no garantizado hasta probar en dispositivo).

## Motor
Godot 4.x, GDScript y renderizador Compatibility (OpenGL).

## Primera etapa
- Isla procedural compacta.
- Control de primera persona.
- Controles táctiles básicos y controles de teclado para pruebas.
- Nodos de recursos recolectables.
- HUD con vida, hambre, sed y mensajes.
- Inventario sencillo.

## Abrir
1. Instala Godot 4.x.
2. Clona o descarga este repositorio.
3. Abre la carpeta del proyecto en Godot.
4. Ejecuta `res://scenes/main.tscn`.

## Android
La exportación APK requiere configurar las plantillas de exportación de Godot, JDK y Android SDK. Se añadirá un flujo de compilación automatizada después de validar la primera escena.

## Licencia
Código del proyecto: MIT. Los recursos externos se incorporarán únicamente cuando sus licencias permitan su redistribución.
