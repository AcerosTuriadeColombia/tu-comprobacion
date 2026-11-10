# TU comprobación

App de comprobación de gastos de Aceros Turia de Colombia S.A.S., conectada a Supabase (proyecto "TU comprobacion", organización Aceros Turia de Colombia).

## Archivos

- `index.html`: la app completa (una sola página). Debe publicarse junto con la carpeta `vendor/`.
- `vendor/`: librerías locales (supabase-js 2.58.0 y JSZip 3.10.1), para no depender de CDNs.
- `supabase/migrations/`: esquema de la base (tablas, permisos, reglas del flujo).
- `supabase/functions/admin-usuarios/`: función de servidor para crear usuarios y restablecer contraseñas.
- `REGLAS-Y-FLUJO.md`: roles, reglas de gasto, ciclo mensual y pendientes.

## Cómo está armada

- **Usuarios**: Supabase Auth. Cada persona entra con un usuario (ej. `ana.gomez`); internamente su correo es `ana.gomez@usuarios.tucomprobacion.app`, que no recibe correos. Solo contabilidad crea usuarios y restablece contraseñas, mediante la función `admin-usuarios`.
- **Datos**: tablas `perfiles`, `gastos`, `periodos`, `anticipos`, `topes`, `centros`. La app solo lee las tablas; toda escritura pasa por funciones de la base (`guardar_gasto`, `enviar_periodo`, `resolver_gastos`, `finiquitar`, etc.) que validan las reglas del flujo. Nadie puede saltárselas desde el navegador.
- **Quién ve qué**: cada persona ve lo suyo; un autorizador ve lo de las personas que tiene asignadas; contabilidad y administración ven todo.
- **Fotos**: bucket privado `tickets`, ruta `<usuario>/<gasto>.jpg`. Se ven con enlaces temporales. Se borran al finiquitar el periodo.

## Puesta en marcha

1. Publicar `index.html` y `vendor/` en una dirección web (ver abajo) o abrir `index.html` directamente para probar.
2. La primera vez, la pantalla de ingreso muestra **Configuración inicial**: crear el usuario de contabilidad. La app muestra una contraseña temporal; al entrar pide cambiarla.
3. Contabilidad da de alta a los demás en **Usuarios** y define quién autoriza a quién.

## Recomendado en el panel de Supabase

- Authentication → Sign In / Providers → Email: desactivar "Allow new users to sign up" (los usuarios solo los crea contabilidad).
- Authentication → Policies (o Password security): longitud mínima 8 y exigir letras y dígitos, para que el servidor aplique la misma regla que la app.
