# Informe técnico de laRVa2 y propuesta de solución del proyecto de multiplicador con _bypass_

Este documento resume cómo está organizado el proyecto `laRVa2_DC`, qué herramientas se necesitan para trabajar con él y cómo abordar punto por punto el enunciado “Diseño e integración en laRVa de un multiplicador con bypass”. El objetivo es servir como guía rápida para comprender el procesador, compilarlo/probarlo y planificar la modificación solicitada.

---

## 1. Visión general del repositorio

| Ruta | Contenido principal |
| --- | --- |
| `laRVa.v` | Núcleo RISC‑V laRVa (RV32E/RV32M opcional). Incluye ALU, control de saltos, banco de registros y las unidades de multiplicación/división (sección `ENABLE_MULDIV`). |
| `system.v`, `uart.v`, `pll.v`, `main.v` | Sistema completo para FPGA ICE40HX8K: memoria RAM interna, UART, wrapper top‑level y PLL. |
| `tb.v`, `tb_divider.v`, `multiplier_4bit_tb.v` | Bancos de pruebas: top completo (`tb.v`), pruebas focalizadas para divisor multiplicador. |
| `Firmware/` | Firmware bare‑metal (C + ensamblador) que se ejecuta en la SoC laRVa. Compila con toolchain RISC‑V (`RISCV-gcc`). |
| `Documentos/Enunciado/*.png` | Enunciado escaneado del proyecto académico. |
| `Documentos/larva_v2/*.png` | Documento técnico del core laRVa v2 (arquitectura, ISA soportada, unidades aritméticas). |

Ficheros auxiliares (`rom.hex`, `rand.hex`, `.asc/.bin/.json`) se generan durante los flujos de simulación y síntesis.

---

## 2. Flujo de trabajo HW/FW

### 2.1 Firmware

1. **Compilación**  
   ```bash
   cd Firmware
   make           # genera code.elf y code.bin
   ```
   El `Makefile` (líneas 1‑28) usa `riscv-none-elf-gcc` con `-march=rv32em` y enlaza según `sections.lds`.

2. **Conversión a ROM**  
   En la raíz, convertir `code.bin` a `rom.hex`:
   ```bash
   ./tovhex.exe Firmware/code.bin rom.hex
   ```
   Esta imagen se carga en la RAM durante simulación (`$readmemh("rom.hex", ...)` en `system.v:146-171`) y se empaqueta con `ICEBRAM` durante la síntesis hardware.

### 2.2 Simulación RTL

El `Makefile` de la raíz (objetivo `sim`) invoca Icarus Verilog con `-DSIMULATION` para compilar `tb.v`. La simulación genera `tb.vcd` y se abre en GTKWave.

Pasos manuales:
```bash
make sim          # compila tb.v + sistema y lanza vvp
```
El testbench (`tb.v:5-70`) inyecta una trama UART sobre `rxd` y vuelca señales internas del banco de registros (`sys1.cpu.regs`), útil para validar el estado de la CPU tras ejecutar el firmware.

### 2.3 Síntesis / bitstream

El objetivo `main.bin` encadena:
1. `yosys` (sintetiza `main.v` + el SoC completo) → `main.json`.
2. `nextpnr-ice40 --hx8k` (colocación/ruteo con `pines.pcf`) → `main.asc`.
3. `icebram` (inyecta ROM) y `icepack` → `main.bin`.

Para programar con `iceload`:
```bash
make burn   # usa ICELOAD -c main.bin
```

### 2.4 Bancos de prueba unitarios

* `multiplier_4bit_tb.v` (realmente ataca al multiplicador completo de laRVa) verifica combinaciones de signo y palabra alta/baja.  
* `tb_divider.v` ejerce la unidad de división con más de 25 casos, incluidos divisiones por cero.

Ambos bancos son auto‑contenidos: basta con compilar con Icarus especificando el testbench correspondiente.

---

## 3. Arquitectura de laRVa v2 (resumen)

La documentación en `Documentos/larva_v2` describe la segunda versión del core con soporte RV32E/RV32M, pipeline de dos etapas y manejo mínimo de privilegios. Resumen de los puntos clave:

1. **Pipeline**: dos etapas superpuestas (fetch/execute). Durante LOAD/STORE/JAL/JALR se inyecta una instrucción inválida para mantener la coherencia del banco de registros (`laRVa.v:89-115`).
2. **Banco de registros**: RV32E (16 registros) direccionado con `rs1/rs2/rd` (`laRVa.v:57-80`). Registro x0 está replicado como 0.
3. **PC doble**: `PCreg0` (modo usuario) y `PCreg1` (modo máquina). `PCci` guarda la dirección de la instrucción en ejecución para calcular saltos (`laRVa.v:236-284`).
4. **Memoria / periféricos** (`system.v:67-140`): 8 KB de RAM replicada en el espacio 0x0000_0000‑0x1FFF_FFFF, periféricos mapeados desde 0xE000_0000 (UART, contador de ciclos, IRQ controller). La interfaz usa `addr[31:2]`, `wstrb[3:0]`, `wdata/rdata`.
5. **Interrupciones** (`laRVa.v:286-333`): lógica tomada del proyecto GUS16. `irqstart` inserta un ciclo de burbuja, `mmode` conmuta PCs y la instrucción `mret` vuelve a modo usuario. `_trap_` agrupa `ecall`, `ebreak` y `brk`.
6. **Señales nuevas v2** (`Documentos/larva_v2/12.png`): `wai` (pausa CPU si un periférico toma el bus) y `vma` (ciclo válido). En esta implementación `clken = ~(wai | mbusy | dbusy)` y `vma = ~(jump | mret | mbusy | dbusy)` cuando `ENABLE_MULDIV` está definido (`laRVa.v:41-52`).

---

## 4. Unidad actual de multiplicación/división

La sección `ENABLE_MULDIV` en `laRVa.v` (aprox. líneas 408‑540) instancia `multiplier` y `divider`. Características:

* **Interfaz**: ambas unidades reciben los operandos tal y como salen de la ALU (`aluIn1`, `aluIn2`), banderas de signo (`funct3`), señal `load` (cuando se detecta opcodes MUL* o DIV*), devuelven `busy` y el resultado 32‑bit.
* **Multiplicador** (figura 5.1.1 del documento):
  * Registros internos: `sha` (multiplicador derecho que se desplaza), `shb` (multiplicando ampliado a 64 bits) y `acc` (acumulador 64 bits).
  * Siempre convierte el multiplicando a valor positivo: `ma = (sma ? (~a) : a) + sma`.
  * Tiene lógica de *caching*: guarda los operandos `oa`, `ob` + banderas `oua`, `oub`. Si la combinación actual coincide, evita recargar (`iload` se desactiva) y presenta instantáneamente el resultado previo.
  * El tiempo depende del número de bits “1” en el multiplicador. Cuando `sha` es 0, `busy` cae y el resultado está en `acc`.
* **Divisor** (figura 5.1.2):
  * Registros `r` (resto), `q` (cociente) y `bct` (contador 6 bit). Consume 33 ciclos (32 iteraciones + carga).
  * También amortigua operandos (`oa`, `ob`, `ous`) para reutilizar resultados si se repite la división.

El bus principal ve estas unidades como periféricos internos: mientras `mbusy` o `dbusy` valen 1 el pipeline se congela y `vma` baja evitando nuevas peticiones de memoria.

---

## 5. Conceptos básicos y “Checklist” para trabajar el enunciado

1. **RISC‑V RV32E/M**: conjunto de registros reducido (x0‑x15) y extensiones MUL/DIV (instrucciones MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU). Ayuda revisar el capítulo 1 del PDF (`larva_v2/1.png`‑`4.png`).
2. **Pipeline y hazard**: laRVa ejecuta una instrucción por ciclo salvo LOAD/STORE/JAL/JALR/MUL/DIV. El multiplicador ocupa el bus durante la operación; por eso cualquier _bypass_ debe garantizar que `mbusy` no se activa cuando se resuelve en 0 ciclos.
3. **Memoria**: el firmware reside en la RAM interna. `rom.hex` se inyecta al arrancar (ver `system.v:146-171`). Esto es relevante si se añade un programa de prueba en `start.s`.
4. **Herramientas**: Icarus + GTKWave para simulación, Yosys/nextpnr/icepack para síntesis. El toolchain RISC‑V debe apuntar a `..\tools\xpack-risc_v\bin\riscv-none-elf-*`.
5. **Tests existentes**: `multiplier_4bit_tb.v` y `tb_divider.v` sirven de referencia para añadir nuevos casos y medir la mejora de latencia cuando se active el bypass.

---

## 6. Resolución propuesta del enunciado

### 6.1 Primera parte – Diseño del componente

**1. Analizar y probar el multiplicador original**

* Utilizar `multiplier_4bit_tb.v` como banco principal. Se puede ampliar con operandos extremos (0, ±1, potencias de dos, patrones repetitivos) y medir ciclos esperando a que `busy` vuelva a 0.  
* Observaciones relevantes:
  * La diferencia entre operar con signo o sin signo está en cómo se extiende el paso de carga (`ma`, `mb`) y en la selección de la palabra alta (`hm`).
  * La unidad ya detecta operandos repetidos (`iload`). Esto evita recargas cuando se repite una multiplicación idéntica.
  * Cuando el multiplicador (`sha`) pasa a 0, la operación termina inmediatamente aunque falten ciclos para 32 iteraciones; esto ocurre cuando el multiplicador original (`a`) tenía pocos bits a 1.

**2. Detectar casos resolubles “rápido”**

Se propone generar una señal `fast_case` que englobe operaciones triviales:

| Caso | Resultado directo | Detección sugerida |
| --- | --- | --- |
| Multiplicador o multiplicando = 0 | 0 (independiente de `hm` salvo high/low) | `a==0 || b==0` |
| Multiplicador = 1 | `b` (signo según `hm`) | `a==1` |
| Multiplicador = -1 (operación con signo) | `-b` (`hm` se queda en extensión de signo) | `(ua==0) && (a==32'hFFFF_FFFF)` |
| Multiplicador potencia de 2 | `b << shift` (low) / `b >> (32-shift)` (high) | `((a & (a-1))==0)` para unsigned |
| Multiplicando potencia de 2 | Rotación simétrica (útil si se pide `hm=1`) | `((b & (b-1))==0)` |

Para cumplir el enunciado, la señal “detecta los casos sencillos” debe valer 1 cuando alguno de los patrones se cumpla. Este bloque combina comparadores y detectores de potencia de dos (AND bit a bit).

**3. Diseñar el circuito con bypass**

Arquitectura propuesta:

```
                 ┌───────────────────────┐
 a,b,ua,ub,hm ──▶│ Lógica fast_case     │─── fast_case
                 │ (comparadores + lzc) │
                 └─────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │ Selector    │
                    │   Load?     │
                    └──────┬──────┘
                           │
                 ┌─────────▼─────────┐
                 │ Multiplicador     │
                 │ secuencial (MD/MR │
                 └─────────┬─────────┘
                           │
        ┌──────────────────▼──────────────────┐
        │ MUX final                           │
        │ fast_case ? fast_result : mul_out   │
        └─────────────────────────────────────┘
```

* `fast_result` se calcula combinacionalmente (sumadores/substracciones sencillas + barrel shifter de 64 bits para los casos potencia de dos).  
* `load_final = load & ~fast_case`. De este modo la unidad secuencial sólo arranca cuando no hay atajo.  
* `busy_final = load_final ? busy_seq : 0`. En caso de bypass, `busy` permanece 0 y el resultado baja en el mismo ciclo que `load`.  
* Para mantener compatibilidad con los puertos originales, el módulo exporta `busy` y `out` idénticos; sólo cambia la ruta interna.

Simulación a realizar:
1. Añadir contadores de ciclos en el banco de pruebas para comprobar que los casos detectados se resuelven en 1 ciclo.
2. Verificar coincidencia con el multiplicador tradicional para inputs aleatorios (usar `rand.hex` o generador en testbench).

### 6.2 Segunda parte – Integración en laRVa y programa de validación

**1. Sustituir el multiplicador en `laRVa.v`**

* Mantener el `module multiplier` original como referencia renombrándolo (`multiplier_seq`) y crear un `multiplier_bypass` con la lógica descrita que instancie internamente al módulo secuencial.
* Cambiar la instancia en `laRVa.v:409-424` para usar el nuevo módulo. `mbusy` debe conectarse a `busy_final`.
* Respetar señales `load`, `ua`, `ub`, `hm` para que `opmul` siga operando igual. En los casos con bypass `mbusy` queda a 0, permitiendo que `clken` no se detenga.

**2. Programa de pruebas en ensamblador (`Firmware/start.s`)**

El enunciado pide “un programa sencillo en ensamblador insertado en start.s que compruebe las 4 operaciones de multiplicación”. Estrategia:

```asm
# start.s — dentro de main()
    la   t0, test_vectors
    la   t1, test_vectors_end
loop_tests:
    lw   t2, 0(t0)      # rs1
    lw   t3, 4(t0)      # rs2
    lw   t4, 8(t0)      # esperado MUL
    lw   t5, 12(t0)     # esperado MULH
    ...                 # idem MULHSU, MULHU
    mul  a0, t2, t3
    bne  a0, t4, fail
    mulh a0, t2, t3
    bne  a0, t5, fail
    ...
    addi t0, t0, 32
    blt  t0, t1, loop_tests
```

* Reservar los vectores en `.data` para incluir casos: 0×N, 1×N, -1×N, potencias de dos, números aleatorios firmados y sin signo.
* Informar el resultado vía UART (reusar `_puts` / `_printf` del firmware en C) o encender un LED si existen periféricos adicionales.
* Tras generar `rom.hex`, ejecutar `make sim` para observar que no aparecen traps y que los registros objetivo toman los valores esperados.

**3. Ajustes de integración**

* Añadir nuevas macros `FAST_MUL` en `laRVa.v` para poder desactivar el bypass si se quiere comparar contra el diseño original.  
* Si se desea medir recursos adicionales, sintetizar con y sin bypass y comparar `sint.log` (`yosys`) en cuanto a LUTs/FFs.

### 6.3 Tercera parte – Documentación e informes

Se recomienda que el informe final incluya:

1. **Análisis del diseño inicial**  
   * Diagrama de bloques (usar los de `larva_v2/3.png` y `larva_v2/11.png`).  
   * Características y limitaciones: ciclos por multiplicación, necesidad de que el multiplicador sea positivo, caching, etc.  
   * Posibles errores: operandos con signo mal extendidos, latencia al reutilizar resultado, estancamiento si `busy` no se libera.

2. **Descripción del nuevo diseño**  
   * Nuevo diagrama mostrando la lógica `fast_case` y el multiplexor de bypass.  
   * Ventajas: reducción de ciclos para casos sencillos, mínima intrusión al pipeline, compatibilidad con interfaz existente.  
   * Coste: comparadores adicionales, barrel shifter de 64 bits (ya reutilizado del ALU o nuevo) y lógica de control.

3. **Características generales y recursos**  
   * Tabla de LUT/FF consumidos antes/después (tomar datos de `sint.log`).  
   * Tabla de ciclos medidos con el banco de pruebas (ej. 0×N → 1 ciclo; potencia de dos → 1 ciclo; casos generales → hasta 33 ciclos).

4. **Estrategia de test**  
   * Validación aislada con `multiplier_4bit_tb.v`.  
   * Validación en sistema completo (`tb.v` + programa en `start.s`).  
   * Repetición de los tests tras síntesis (capturando la UART del FPGA real para demostrar correcto funcionamiento).

5. **Presentación**  
   * El enunciado solicita una presentación en PowerPoint resumiendo todo el flujo; se puede reutilizar gráficos del informe y capturas de GTKWave/terminal.

---

## 7. Plan detallado de trabajo

1. **Revisión y limpieza**  
   * Confirmar que `rom.hex` y `rand.hex` están en sincronía con la última compilación del firmware.  
   * Añadir scripts para ejecutar `multiplier_4bit_tb` y `tb_divider` desde `make`.

2. **Implementación del multiplicador con bypass**  
   * Crear módulo nuevo (`multiplier_fast.v` o similar) con la lógica propuesta.  
   * Integrar en `laRVa.v` bajo `ENABLE_MULDIV`.  
   * Añadir parámetros para activar/desactivar detección (`FAST_DETECT_ZERO`, etc.).

3. **Verificación en simulación**  
   * Ampliar `multiplier_4bit_tb.v` registrando número de ciclos y comparando con el multiplicador original.  
   * Ajustar `tb.v` si se quiere observar la UART mostrando los resultados del programa ensamblador.

4. **Firmware de pruebas**  
   * Añadir un bloque en `start.s` para ejecutar las 4 instrucciones MUL*.  
   * En `main.c`, mostrar por UART el “PASS/FAIL” global y, opcionalmente, los operandos fallidos.

5. **Síntesis y mediciones**  
   * Ejecutar `make main.bin` con y sin bypass.  
   * Registrar LUT/FF en tabla.  
   * Si se dispone de placa, probar `make burn` y observar la UART para confirmar que el firmware declara “PASS”.

6. **Documentación final**  
   * Redactar informe con capítulos solicitados.  
   * Preparar presentación y anexar ficheros necesarios para la entrega en el campus virtual.

---

## 8. Recursos y conocimientos previos recomendados

* **RISC‑V Privileged ISA (sección mínima)**: entender `mret`, `csrrw` y registros `mepc`. El core implementa un subconjunto muy pequeño (ver `larva_v2/5.png`).  
* **Diseño digital secuencial**: registro desplazador + sumador para multiplicadores de Booth/shift‑add y divisiones resta‑shift.  
* **Herramientas FPGA**: flujo open‑source para ICE40 (Yosys → nextpnr → icepack).  
* **Depuración UART**: el firmware imprime menús por consola; el test propuesto se puede verificar leyendo la salida serial a 115200 baudios.

---

## 9. Próximos pasos inmediatos

1. Preparar entorno de simulación (`make sim`) y verificar que el firmware actual arranca sin el nuevo hardware.  
2. Implementar la lógica `fast_case` en un módulo nuevo y conectarla al multiplicador existente.  
3. Crear los patrones de prueba en ensamblador y automatizar la comparación de resultados.  
4. Reunir datos de latencia y recursos para el informe/presentación.  
5. Entregar documentación completa (informe + PowerPoint) según la tercera parte del enunciado.

Con esta hoja de ruta se cubren todos los apartados pedidos y se dispone de la información necesaria para comprender, modificar y verificar el procesador laRVa dentro del contexto académico del proyecto final.

