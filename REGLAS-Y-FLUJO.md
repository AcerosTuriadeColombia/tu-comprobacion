# TU comprobación — Reglas, condiciones y flujo de trabajo

Versión 0.4 · Aceros Turia de Colombia S.A.S. · Pendiente de revisión antes de publicar

## 1. Roles

| Rol | Puede | No puede |
|---|---|---|
| Vendedor | Registrar gastos del periodo, editar/eliminar mientras esté abierto, enviar periodo a autorización, solicitar anticipo | Autorizar, ver gastos de otros |
| Líder | Lo del vendedor + autorizar a sus vendedores | Autorizar gastos de sí mismo (lo autoriza el dueño) |
| Autorizador | Revisar y aprobar/devolver gasto por gasto de las personas que tiene asignadas | Registrar pagos |
| Contabilidad | Alta y edición de usuarios, matriz de autorización (quién autoriza a quién), restablecer contraseñas, confirmar depósito de anticipos, finiquitar periodo, registrar pago de tarjeta, exportar | Crear gastos ajenos |
| Administrador | Políticas, centros de costos, cajas menores, dashboard | — |

Los autorizadores no se fijan por nombre en la app: contabilidad los asigna en la matriz de usuarios. Pueden ser autorizadores los usuarios con rol Líder, Autorizador o Administrador. Nadie puede autorizarse a sí mismo. Un vendedor o líder sin autorizador asignado no puede enviar su periodo.

## 2. Usuarios

Contabilidad da de alta a todos los usuarios. Cada usuario tiene: nombre, puesto, rol, correo (opcional, solo referencia), quién lo autoriza, tipo de pago (tarjeta de crédito o anticipo), centro de costos (Planta Amagá, Planta Malambo, Comercial), saldo de crédito (si es tarjeta) y política según rol.

- Cajas menores se dan de alta como usuario con rol "Caja menor": planta, encargado, monto fijo (2.000.000 COP, por confirmar) y autorizador.
- Cada usuario tiene un nombre de usuario para ingresar y un celular para los avisos por WhatsApp.
- Al crear un usuario, la app genera una contraseña temporal que contabilidad entrega a la persona.
- Recuperación de contraseña: solo contabilidad la restablece y entrega una temporal.
- Los usuarios que salen de la empresa se desactivan (no se borran) para conservar su historial.

## 3. Acceso

- Ingreso con usuario y contraseña.
- Cambio de contraseña en el primer ingreso y cada 90 días.
- Mínimo 8 caracteres, con letras y números.
- Bloqueo tras 5 intentos fallidos hasta que contabilidad lo desbloquee.
- Cierre de sesión tras 30 minutos de inactividad.

## 4. Conceptos y reglas de gasto

Conceptos: Desayuno, Almuerzo, Comida con cliente, Café con cliente, Peaje, Combustible, Parqueadero, Obsequio, Hospedaje.

- Comida con cliente y café con cliente: casilla "con cliente", empresa y nombres de las personas. Presupuesto por persona.
- Obsequio: nombre del cliente obligatorio.
- Desayuno, almuerzo y comida individual: solo aplican fuera de la ciudad de residencia o cuando la persona pasa la noche fuera de casa. La app pide marcar "fuera de ciudad" o "pernocta".
- No se reconoce: licor, gastos personales, antojos de media mañana o tarde.
- Topes por concepto: configurables; quedan vacíos hasta recibir la política de inventario.
- Si el gasto excede el tope, la app pide comentario con el detalle antes de guardar.
- Moneda por defecto: COP.
- Fecha por defecto: hoy; editable; debe coincidir con la fecha del ticket.
- Centro de costos obligatorio en cada gasto.

## 5. Comprobantes

- Se adjunta la imagen del ticket y se captura el valor total.
- La app lee fecha y valor de la imagen como sugerencia; la persona confirma antes de guardar. (Pendiente; por ahora se capturan a mano.)
- Casilla "factura enviada al correo de la empresa".
- Pagos en efectivo permitidos cuando el lugar no acepta tarjeta (peajes, parqueaderos y similares). Se marca el medio de pago por gasto.
- Las cajas menores llevan foto por cada gasto.

## 6. Ciclo mensual (periodo)

1. **Abierto.** Los gastos se registran y acumulan durante el mes. Se pueden editar y eliminar. No se envía nada a autorización.
2. **Enviado.** Al cerrar el mes, la persona revisa el total del periodo y lo envía de una sola vez. Al enviar, aparece "Avisar al autorizador" por WhatsApp con mensaje prearmado (ej. "Comprobación agosto completada"). Los gastos quedan bloqueados.
3. **En revisión.** El autorizador aprueba o devuelve gasto por gasto (casilla individual, selección múltiple o "seleccionar todo"). Si devuelve un gasto, debe incluir comentario y la persona corrige solo ese gasto.
4. **Autorizado.** Todos los gastos aprobados. Pasa a contabilidad.
5. **Finiquitado.** Contabilidad cierra el periodo y registra el pago de la tarjeta, o confirma el depósito/devolución del anticipo.

Cada gasto pertenece al mes de la fecha de su ticket. La persona elige el periodo (mes) en la app; al inicio de mes la app abre por defecto el mes anterior si tiene gastos sin enviar.

Al reenviar un periodo devuelto, solo se revisan los gastos corregidos; los ya aprobados no se tocan.

Plazo de radicación: los primeros 5 días del mes. La app avisa cuando se acerca la fecha y muestra periodos pendientes.

## 7. Tipos de pago

**Tarjeta de crédito.** El comercial comprueba sus gastos del mes anterior los primeros 5 días del mes si tuvo gastos. Cada gasto descuenta del saldo de la tarjeta. Contabilidad registra el pago y el saldo se actualiza.

**Anticipo.**
- El vendedor solicita el monto (con motivo). Se notifica a contabilidad por WhatsApp.
- El jefe directo autoriza.
- Contabilidad deposita y confirma en la app.
- Si el anticipo anterior no está comprobado, no se puede solicitar otro.
- Al comprobar: si sobra, se devuelve los primeros días del mes; si falta, se deposita el faltante (solo si está autorizado).

**Caja menor.** El encargado registra cada gasto con foto. Debe mantener el monto fijo; lo que se gasta se repone con comprobación.

## 8. Notificaciones (sin correo corporativo)

- Solicitud de anticipo: botón WhatsApp a contabilidad.
- Periodo enviado: botón WhatsApp al autorizador.
- Periodo devuelto: botón WhatsApp del autorizador al colaborador.
- Periodo autorizado y anticipo autorizado: botón WhatsApp a contabilidad.
- Anticipo depositado: botón WhatsApp de contabilidad al colaborador.
- Recordatorio de radicación: contabilidad ve quién no ha enviado el mes anterior y tiene botón para recordarle.

## 9. Exportación y datos

- Cada mes contabilidad exporta el periodo a Excel/CSV con las imágenes (ZIP).
- Después de finiquitar, las imágenes se borran de la base y solo quedan montos y metadatos, para no acumular espacio.
- Dashboard de administración: gasto por concepto, por planta/centro de costos, por persona, saldos de tarjeta, anticipos pendientes.

## 10. Pendientes antes de producción

- Definir en la matriz quién autoriza a cada comercial y a cada líder.
- Encargados de caja menor por planta (Amagá y Malambo).
- Monto definitivo de cada caja menor (hoy 2.000.000 COP).
- Política de montos por concepto y rol (inventario). El administrador ya puede cargar topes por concepto en Políticas.
- Formato exacto que pide contabilidad para el ERP.
- Publicar la app en una dirección web para los usuarios (el repositorio y el proyecto Supabase ya existen).
- Lectura automática de fecha y valor del ticket.
