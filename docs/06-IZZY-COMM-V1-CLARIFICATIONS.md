# IZZY Communications Compensation Plan v1.0 — Addendum Aclaratorio (V1.0 Clarification Addendum)

**Versión del plan:** IZZY-COMM-2026-10-V1 (sin cambio de versión; este addendum NO es V1.1)  
**Estado:** APPROVED — V1.0 CLARIFICATION ADDENDUM  
**Aprobado por:** Moisés Caicedo  
**Fecha de aprobación:** 2026-10-06  
**Naturaleza:** aclaración de reglas existentes. No es un cambio económico.

## 1. Alcance y precedencia

1. Este documento aclara el significado de reglas ya aprobadas en los documentos 01–05. No modifica montos, tablas de comisiones, bonos, tramos, productos ni períodos.
2. Los documentos 01–05 permanecen congelados e intactos. Si existiera conflicto aparente, prevalece el documento 01 y este addendum se interpreta de forma compatible con él.
3. Este addendum se agrega a la documentación V1 sin crear una nueva versión del plan.

## 2. Definiciones

| Término | Definición |
|---|---|
| `supervisor_id` | Relación que gobierna la estructura económica: determina el pool 25/50, la base elegible y el receptor del Bono de Liderazgo. |
| `sponsor_id` | Relación de reclutamiento/origen. Se conserva como dato histórico; no gobierna por sí sola la estructura económica. |
| Desarrollar a un agente | Reclutarlo y tenerlo como agente directo bajo el propio `supervisor_id`. |
| Supervisor directo (hacia abajo) | Supervisor cuyo `supervisor_id` efectivo es el Supervisor en cuestión. En los documentos 01–05, "Supervisor directo" se usa en este sentido descendente: el Supervisor que uno desarrolló, no el jefe de uno. |
| Base elegible de un Supervisor S | Conexiones válidas cuyo vendedor es un agente en rango Entrenamiento o Asociado con `supervisor_id = S` en la referencia económica (sección 5). No incluye vendedores que sean Supervisores ni las bases de esos Supervisores. |
| Internet | Producto de servicio de internet según la sección 4. |

## 3. Bono de Liderazgo: reglas aclaradas

Monto, producto y profundidad no cambian: $5 por conexión válida elegible de internet; una sola profundidad (documento 01, sección Liderazgo).

1. **Los agentes directos de un Supervisor no generan Bono de Liderazgo para ese Supervisor.** Sus conexiones cuentan para el pool de producción 25/50 del Supervisor.
2. **El Bono de Liderazgo comienza cuando un Supervisor desarrolla a un agente y ese agente asciende a Supervisor.**
3. **Desde ese momento**, el Supervisor que lo desarrolló recibe $5 por cada conexión válida elegible de internet producida por:
   - ese Supervisor (producción personal);
   - la base elegible de ese Supervisor, es decir, sus agentes directos que todavía no son Supervisores.
4. **Salida de la base por ascenso.** Si un agente de esa base asciende a Supervisor, desde su fecha y hora efectiva sale de la base elegible. Para sus conexiones validadas a partir de ese momento, el receptor del liderazgo es el Supervisor inmediatamente superior a él (su `supervisor_id`), y el Supervisor anterior recibe $0 de liderazgo sobre ese Supervisor y su base.
5. **Una sola profundidad.** No existe liderazgo ilimitado hacia abajo: un Supervisor no recibe liderazgo sobre los Supervisores desarrollados por el Supervisor que él desarrolló, ni sobre sus bases.
6. **Un solo Bono de Liderazgo por conexión**, acreditado a un único receptor.
7. **El receptor debe ser Supervisor** en la referencia económica de la conexión (sección 5).

## 4. Productos de liderazgo

| Elegibles — $5 | No elegibles — $0 |
|---|---|
| Spectrum 500 Mbps | AT&T Celular + Línea |
| Spectrum 1 Gig | AT&T BYOD |
| AT&T Fiber 300 Mbps | |
| AT&T 500 Mbps | |
| AT&T 1–5 Gig | |
| AT&T Air | |
| Frontier 500 Mbps | |
| Frontier 1 Gig | |

**D-06 (APROBADA 2026-10-06, Opción 1):** AT&T Air se clasifica como INTERNET y su `leadership_eligible` es `TRUE`.

## 5. Referencia económica (D-04)

**D-04 (APROBADA 2026-10-06):** el ancla del snapshot económico es `validation_date`.

- El rango, el receptor y la jerarquía aplicables a una conexión quedan congelados cuando la conexión es validada, salvo corrección administrativa documentada.
- No existe recálculo histórico por promociones o cambios de jerarquía posteriores.
- Las conexiones anteriores a un ascenso conservan el rango, sponsor, jerarquía y reglas económicas existentes cuando fueron generadas o validadas (documento 01, sección Ascensos y mantenimiento).
- El ascenso opera con fecha y hora efectiva: una conexión validada antes de esa fecha y hora se evalúa con el rango anterior; una validada después, con el nuevo.

## 6. Mantenimiento trimestral y liderazgo (D-16)

**D-16 (APROBADA 2026-10-06, Opción 1):** el requisito trimestral de 150 conexiones NO condiciona, por sí solo, el pago del Bono de Liderazgo de $5. Si la conexión cumple las reglas de liderazgo, se paga el $5 aunque el Supervisor receptor no haya cumplido las 150 conexiones del trimestre anterior.

**Lo que esta decisión NO define** (queda como decisión separada del owner, sin regla vigente):

- la consecuencia general de no mantener las 150 conexiones;
- cualquier pérdida de rango, período de gracia, retención de comisiones o aplicación retroactiva.

Ninguna de esas consecuencias debe asumirse ni implementarse hasta que el owner la decida expresamente.

## 7. Ejemplos

A desarrolló a B (Supervisor). C es agente directo de B.

1. B vende un servicio de internet elegible: A recibe $5.
2. C vende un servicio de internet elegible: A recibe $5. B no recibe liderazgo; las conexiones de C cuentan en el pool 25/50 de B.
3. C asciende a Supervisor con fecha y hora efectiva T. C vende internet elegible con `validation_date` posterior a T: B recibe $5 y A recibe $0 de liderazgo sobre C y su base. Una conexión de C validada antes de T conserva su receptor original (A).
4. B o C venden AT&T Celular + Línea o AT&T BYOD: nadie recibe liderazgo ($0).
5. Un agente directo de A vende internet: A no recibe Bono de Liderazgo; la conexión cuenta en el pool 25/50 de A.

## 8. Registro de decisiones incorporadas

| ID | Tema | Estado |
|---|---|---|
| D-04 | Ancla del snapshot económico: `validation_date` | APPROVED 2026-10-06 |
| D-06 | AT&T Air = internet; elegible para liderazgo | APPROVED 2026-10-06 (Opción 1) |
| D-16 | Mantenimiento de 150 no condiciona por sí solo el liderazgo | APPROVED 2026-10-06 (Opción 1) |
| — | `supervisor_id` gobierna la economía; `sponsor_id` es reclutamiento/origen | APPROVED 2026-10-06 (sin cambio de schema) |
| — | Definición de base elegible | APPROVED 2026-10-06 |
