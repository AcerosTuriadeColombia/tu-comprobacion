# TU comprobación

App de comprobación de gastos de Aceros Turia de Colombia S.A.S.

- `index.html`: prototipo funcional. Abrir directo en el navegador (doble clic). Los datos y las fotos quedan en el navegador de ese equipo (`localStorage`), así que cada equipo ve sus propios datos de prueba.
- `vendor/jszip.min.js`: librería para generar el ZIP de exportación (sin depender de internet).
- `REGLAS-Y-FLUJO.md`: roles, reglas de gasto, ciclo mensual y pendientes antes de producción.

## Usuarios de prueba

Contraseña de todos: `demo`.

| Usuario | Rol | Notas |
|---|---|---|
| contabilidad | Contabilidad | Alta de usuarios, matriz de autorización, anticipos, finiquito, exportación |
| admin | Administrador | Dashboard, topes por concepto, centros de costos |
| autorizador | Autorizador | Autoriza al líder y a la caja menor |
| lider | Líder | Pago por anticipo; autoriza al vendedor |
| vendedor | Vendedor | Tarjeta de crédito; trae 2 gastos del mes anterior |
| caja.amaga | Caja menor | Planta Amagá, monto fijo 2.000.000 |

Para volver a empezar con los datos de prueba, borrar los datos del sitio en el navegador.

## Producción

Prevista en Supabase: Auth (usuarios y contraseñas), tablas, Storage para fotos de tickets y lectura automática de fecha y valor del ticket.
