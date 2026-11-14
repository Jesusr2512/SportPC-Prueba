# 🧪 SportPC — Prototipo de Prueba (Wii / Switch Sports para PC)

> ⚠️ **AVISO:** Este repositorio es una **PRUEBA / PROTOTIPO EXPERIMENTAL** en desarrollo temprano. Las mecánicas, controles de movimiento y gráficos están en fase de testeo y ajuste continuo.

Prototipo experimental en **Godot Engine 4.7** inspirado en **Nintendo Switch Sports** y **Wii Sports Resort**, centrado inicialmente en el minijuego **Chambara (Duelo de Espadas)** con soporte para sensores de movimiento (**Six-Axis / Giroscopio**).

---

## ✨ Qué incluye esta prueba

- **Modo Chambara (1P vs IA y 2P Local)**:
  - Carril de duelo 1D sobre plataforma flotante con avance automático tras empujes.
  - Cortes alineados al ángulo de la espada (`0°`, `±45°`, `±90°`).
  - Bloqueo perpendicular con aturdimiento y carga de contraataque, choque de espadas, guardia superada paralela y combo multi-golpe.
  - Tres niveles de dificultad de IA (`Novato`, `Pro`, `Campeón`).
- **Controles de movimiento y periféricos**:
  - **Móvil por Wi-Fi (`HTTPS + WebSocket` en el puerto `8443`)**: convierte cualquier smartphone con navegador y giroscopio en un mando inalámbrico desde `web/mobile_controller.html`.
  - **Mandos con giroscopio / Gamepad** y **modo Ratón + Teclado** para pruebas rápidas sin sensor.
- **Pruebas automáticas headless**:
  - Batería de verificación en `tests/SmokeTest.tscn` (`tests/smoke_test.gd`).

---

## 🛠️ Requisitos y cómo ejecutar esta prueba

1. Tener instalado **Godot Engine 4.7+** (por ejemplo, `Godot_v4.7.2-stable_win64.exe`).
2. Abrir `project.godot` desde Godot (o en Windows ajustar la ruta en `Jugar_SportPC.bat` / `Abrir_Editor_Godot.bat`).
3. Para usar el **móvil como mando**:
   - Inicia el juego primero en el PC para activar el servidor local en el puerto `8443`.
   - Conecta el móvil a la misma red Wi-Fi y entra a la URL `https://<IP-de-tu-PC>:8443` mostrada en pantalla (aceptando el certificado autofirmado local).
