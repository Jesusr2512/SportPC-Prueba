# 🧪 SportPC — Prototipo de Prueba (Wii / Switch Sports para PC)

> ⚠️ **AVISO:** Este repositorio es una **PRUEBA / PROTOTIPO EXPERIMENTAL** en desarrollo temprano. Las mecánicas, controles de movimiento y gráficos están en fase de testeo y ajuste continuo.

Prototipo experimental en **Godot Engine 4.7** inspirado en **Nintendo Switch Sports** y **Wii Sports Resort**, centrado en **Chambara (Duelo de Espadas 3D)** con fusión 3D de giroscopio en tiempo real y mando móvil inalámbrico.

---

## ✨ Qué incluye esta prueba (Enfoque Renovado)

- **Detección Física Realista 1:1 (`MotionFusion` + `MotionHub`)**:
  - Seguimiento completo por **cuaterniones 3D** con corrección de horizonte sin bloqueo angular cuando sujetas el móvil inclinado (~45°–75°).
  - Cálculo de velocidad en la **punta de la espada** (`ω × punta`): girar la muñeca para orientar la hoja produce cero ataques falsos, mientras que un látigo rápido dispara el tajo de inmediato.
  - Combos en vaivén al cambiar dirección sin esperar a detener la mano, captura de picos de giro entre paquetes WebSocket (`60Hz+`) y detección de **Estocada frontal**.
- **Combate Táctico en 3D**:
  - **Guardia Activa vs. Parry Perfecto**: pulsa Guardia en cruz perpendicular al golpe en `< 0.22s` para activar cámara lenta (`0.25x`), aturdir al rival `1.65s` y cargar contraataque.
  - **Medidor de Guardia y Rotura**: los golpes paralelos desgastan y rompen la postura del defensor.
  - **Estocada** (perfora guardia estática), **Esquiva lateral con invulnerabilidad** (`i-frames`) y **Onda de Espada Maestra** al completar el 100% de Espíritu.
  - Dos estilos de combate (`Chambara Clásico` y `Espadas Gemelas`) y cuatro niveles de IA (`Novato`, `Pro`, `Campeón`, `Leyenda`).
- **3 Escenarios 3D + Pantalla Dividida 2P**:
  - **Isla del Sol**, **Puente Volcánico** y **Santuario Flotante** (con balanceo dinámico e shader animado de agua/lava/cielo).
  - Cámara dividida automática para **2 Jugadores Locales** con mando o móvil.
- **Dojo de Práctica 3D Interactivo (`CalibrationRoom.tscn`)**:
  - Entrenamiento paso a paso en vivo junto a un **Muñeco de Entrenamiento 3D** que cambia ángulos de guardia y reacciona en tiempo real a cortes, estocadas y roturas.
- **Mando Móvil por Wi-Fi (`HTTPS + WebSocket` puerto `8443`, `web/mobile_controller.html`)**:
  - Modos **2 Manos** (joystick táctil + deslizar para esquivar + botón de guardia) y **1 Mano**, soporte iOS/Android (`Chrome` / `Samsung Internet` / `Safari`), dial en vivo sincronizado desde Godot y botones de `Estocada` y `Esquiva`.
- **Pruebas automáticas headless**:
  - Batería completa en [`tests/SmokeTest.tscn`](tests/SmokeTest.tscn) ([`tests/smoke_test.gd`](tests/smoke_test.gd)).

---

## 🛠️ Requisitos y cómo ejecutar esta prueba

1. Tener instalado **Godot Engine 4.7+** (por ejemplo, `Godot_v4.7.2-stable_win64.exe`).
2. Abrir `project.godot` desde Godot (o en Windows ajustar la ruta en `Jugar_SportPC.bat` / `Abrir_Editor_Godot.bat`).
3. Para usar el **móvil como mando**:
   - Inicia el juego en el PC para activar el servidor local en el puerto `8443`.
   - Conecta el móvil a la misma red Wi-Fi, abre `https://<IP-de-tu-PC>:8443`, acepta el certificado local y pulsa **Activar Sensores**.
