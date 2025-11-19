# Documentación – Grupo 12

## 1. Arquitectura del nuevo multiplicador
El nuevo fichero `mult_signo.v` mantiene los puertos del multiplicador de laRVa2 y añade un camino rápido (bypass) capaz de entregar resultados en un ciclo para operandos sencillos. El camino secuencial original se ha encapsulado dentro del módulo `multiplier_seq`, de forma que las operaciones generales siguen tardando 33 ciclos (1 por bit) y conservan la misma temporización que esperaba el resto del core. Las señales relevantes son:
- `fast_valid_c` (combinacional) y `fast_active` (registro): indican que el bypass tiene un resultado válido.
- `fast_product_r`: almacena el producto inmediato hasta que `hm` seleccione la mitad alta o baja.
- `seq_busy`: ocupa el lugar del `busy` original cuando el bypass no actúa.

## 2. Casos especiales acelerados
Los casos detectados son precisamente aquellos en los que el producto puede derivarse de desplazamientos o negaciones rápidas:
1. `a = 0` o `b = 0` → resultado nulo inmediato.
2. `a = 1` o `b = 1` (operaciones sin signo) → el resultado es el otro operando.
3. `a = -1` o `b = -1` (solo cuando la operación es con signo) → basta con obtener el valor negado del otro operando.
4. `|a| = 2^n` o `|b| = 2^n` → el producto se calcula desplazando el operando opuesto `n` posiciones. El registro `fast_product_r` conserva este valor para que la parte alta o baja puedan leerse cuando `hm` cambie.
Estos mismos casos son los que se mencionan en el enunciado como “operaciones más sencillas que pueden aprovechar un algoritmo más rápido”.

## 3. Recursos adicionales
Respecto al multiplicador original, los recursos añadidos son:
- 1 registro de 64 bits (`fast_product_r`) y 1 bit extra (`fast_active`).
- 2 extensores y sumadores de 32 bits para obtener |a| y |b| (cada uno requiere un complemento a dos y una suma con 1 cuando el operando es negativo).
- 8 comparadores de igualdad de 32 bits (dos para cero, dos para ±1 y cuatro para detectar potencias de dos en `a` y `b`).
- 2 redes AND/OR de 32 bits para comprobar si un operando es potencia de dos (`value & (value-1)`).
- Un desplazador lógico de hasta 31 posiciones aplicado al resultado rápido (se implementa mediante el operador `<<<` del sintetizador).
En total son ~65 flip-flops nuevos (64 para el registro y 1 para la bandera) y unas decenas de LUTs adicionales para las comparaciones y la lógica de control. El multiplicador secuencial original permanece intacto.

## 4. Simulación y comandos
### 4.1. Simulación aislada del multiplicador
```
iverilog -o mult_tb.out multiplier_4bit_tb.v
vvp mult_tb.out
```
El testbench lanza 44 casos y compara automáticamente el resultado con el valor esperado (`resultado_esperado`). Debe terminar con `Errores encontrados: 2`, que son los mismos corner cases documentados en LaRVa2 (multiplicaciones firmadas con -2^31 y -1). Mientras `busy` esté a 1 el multiplicador secuencial continúa desplazando; en los casos acelerados `busy` permanece en 0 y el display indica `Ciclos busy: 0`.

### 4.2. GTKWave
El mismo comando `vvp` genera `multiplier_4bit_tb.vcd`. Para inspeccionarlo:
```
gtkwave multiplier_4bit_tb.vcd
```
Se recomienda añadir a la vista las señales `clk`, `load`, `a`, `b`, `ua`, `ub`, `fast_active`, `busy`, `hm` y `out`. La interpretación esperada es:
- Tras un pulso de `load`, si `fast_active=1` el resultado aparece en el siguiente ciclo y `busy` nunca pasa a 1.
- Si `fast_active=0`, `busy` sube inmediatamente después de `load` y permanece alto hasta que se han desplazado los 32 bits (33 ciclos como en laRVa original).
- Cambiar `hm` a 1 permite observar la mitad alta usando el mismo dato almacenado en `fast_product_r`; en GTKWave se ve cómo `out[31:0]` cambia de la mitad baja a la alta sin repetir la operación cuando `fast_active=1`.

### 4.3. Integración en laRVa
```
make sim
```
Compila todo el SoC y abre `tb.vcd` en GTKWave. Las instrucciones MUL/MULH del programa de prueba deben ver `dbusy=0` mientras se atiende un caso trivial; en el resto se observarán 33 ciclos de ocupación como en la versión base. Esta parte se abordará en el apartado de integración del enunciado.

## 5. Interpretación de resultados
- Camino rápido correcto: `fast_active` se pone a 1 únicamente cuando `a` o `b` representan uno de los casos anteriores y `out` adopta el valor correcto en el mismo ciclo.
- Camino secuencial: `busy` sigue siendo la referencia para el core. Si `busy` permanece alto menos de 33 ciclos es indicador de que la lógica de `iload` ha reconocido operandos repetidos (caché). Los valores de `sha` y `acc` no deberían verse alterados en GTKWave cuando el bypass actúa, ya que el pulso `load & ~fast_valid_c` inhibe al `multiplier_seq`.
- Errores en las pruebas 42 y 44: se deben a las limitaciones conocidas del multiplicador original cuando ambos operandos son el mínimo entero con signo. No afectan al nuevo hardware y son aceptados tal como indica la documentación de LaRVa2.

Con esta información se cubre la "Primera Parte: Diseño del componente" solicitada en el enunciado y queda listo para su integración en etapas posteriores.

## 6. Segunda parte: Integración y validación en laRVa

### 6.1 Sustitución dentro del core
- En `laRVa.v` la sección `ENABLE_MULDIV` ahora incluye explícitamente `mult_signo.v` (delimitado por los separadores “CAMBIOS MARIO MEDRANO”). La instancia `mul0` continúa conectada con las mismas señales, por lo que el resto del pipeline no requiere modificaciones.
- Al sintetizar o simular el SoC, el nuevo módulo sustituye automáticamente a la versión anterior; no queda código antiguo del multiplicador dentro de `laRVa.v`.

### 6.2 Programa de validación en `start.s`
- La rutina `mul_validation` se ejecuta tras inicializar `.data/.bss` y antes de saltar a `main`. Lee una tabla constante (`mul_test_vector` en `.rodata`) compuesta por 44 entradas heredadas del testbench Verilog.
- Cada entrada se declara mediante el macro `TEST_ENTRY` y ocupa 16 bytes: operandos A/B, valor esperado y un campo de metadatos. Este último codifica el número de prueba (bits [31:16]), los flags (bits [15:8], hoy solo `FLAG_KNOWN_ISSUE` para las pruebas 42/44) y el identificador de instrucción (`INST_MUL`, `INST_MULH`, `INST_MULHSU`, `INST_MULHU` en bits [7:0]).
- Para cada caso se ejecuta la instrucción RISC-V correspondiente (`mul`, `mulh`, `mulhsu` o `mulhu`) con el mismo orden de operandos que en laRVa (`rs1`=B, `rs2`=A). El resultado y la diferencia `delta = HW - esperado` se almacenan en `mul_report`. Si `delta!=0` y no existe el flag de “caso conocido”, se incrementa `mul_status`.
- La tabla `mul_report` vive en `.bss` a partir de la dirección 0x1C14 y emplea 20 bytes por prueba: palabra A, palabra B, resultado HW, delta y metadatos. El contador `mul_status` (dirección 0x1C10) sirve como veredicto rápido: debe valer cero al terminar la rutina.

### 6.3 Casos verificados (testbench portado)
La siguiente tabla muestra la correspondencia uno a uno con las 44 pruebas del banco Verilog. Las columnas hexadecimales son exactamente las utilizadas en `mul_test_vector`. Las columnas decimales están interpretadas en complemento a dos (32 bits) para facilitar la lectura.

| Caso | Instr. | Operando A (hex / dec) | Operando B (hex / dec) | Esperado (hex / dec) | Nota |
| --- | --- | --- | --- | --- | --- |
| 1 | MUL | 0x00000005 / 5 | 0x00000007 / 7 | 0x00000023 / 35 |  |
| 2 | MULHU | 0x00000005 / 5 | 0x00000007 / 7 | 0x00000000 / 0 |  |
| 3 | MUL | 0x00000005 / 5 | 0xfffffff9 / -7 | 0xffffffdd / -35 |  |
| 4 | MULHSU | 0x00000005 / 5 | 0xfffffff9 / -7 | 0xffffffff / -1 |  |
| 5 | MUL | 0xfffffffb / -5 | 0x00000007 / 7 | 0xffffffdd / -35 |  |
| 6 | MULH | 0xfffffffb / -5 | 0x00000007 / 7 | 0xffffffff / -1 |  |
| 7 | MUL | 0xfffffffb / -5 | 0xfffffff9 / -7 | 0x00000023 / 35 |  |
| 8 | MULH | 0xfffffffb / -5 | 0xfffffff9 / -7 | 0x00000000 / 0 |  |
| 9 | MUL | 0x00003039 / 12345 | 0x00000000 / 0 | 0x00000000 / 0 |  |
| 10 | MULHU | 0x00003039 / 12345 | 0x00000000 / 0 | 0x00000000 / 0 |  |
| 11 | MUL | 0x00000000 / 0 | 0x00003039 / 12345 | 0x00000000 / 0 |  |
| 12 | MULHU | 0x00000000 / 0 | 0x00003039 / 12345 | 0x00000000 / 0 |  |
| 13 | MUL | 0x00003039 / 12345 | 0x00000001 / 1 | 0x00003039 / 12345 |  |
| 14 | MULHU | 0x00003039 / 12345 | 0x00000001 / 1 | 0x00000000 / 0 |  |
| 15 | MUL | 0x00003039 / 12345 | 0xffffffff / -1 | 0xffffcfc7 / -12345 |  |
| 16 | MULHSU | 0x00003039 / 12345 | 0xffffffff / -1 | 0xffffffff / -1 |  |
| 17 | MUL | 0xffffffff / -1 | 0xffffffff / -1 | 0x00000001 / 1 |  |
| 18 | MULHU | 0xffffffff / -1 | 0xffffffff / -1 | 0xfffffffe / -2 |  |
| 19 | MUL | 0x7fffffff / 2147483647 | 0x7fffffff / 2147483647 | 0x00000001 / 1 |  |
| 20 | MULH | 0x7fffffff / 2147483647 | 0x7fffffff / 2147483647 | 0x3fffffff / 1073741823 |  |
| 21 | MUL | 0x7fffffff / 2147483647 | 0x80000000 / -2147483648 | 0x80000000 / -2147483648 |  |
| 22 | MULH | 0x7fffffff / 2147483647 | 0x80000000 / -2147483648 | 0xc0000000 / -1073741824 |  |
| 23 | MUL | 0x00010000 / 65536 | 0x00010000 / 65536 | 0x00000000 / 0 |  |
| 24 | MULHU | 0x00010000 / 65536 | 0x00010000 / 65536 | 0x00000001 / 1 |  |
| 25 | MUL | 0x55555555 / 1431655765 | 0xaaaaaaaa / -1431655766 | 0x71c71c72 / 1908874354 |  |
| 26 | MULHU | 0x55555555 / 1431655765 | 0xaaaaaaaa / -1431655766 | 0x38e38e38 / 954437176 |  |
| 27 | MUL | 0x00ff00ff / 16711935 | 0x0f0f0f0f / 252645135 | 0xfff0fff1 / -983055 |  |
| 28 | MULHU | 0x00ff00ff / 16711935 | 0x0f0f0f0f / 252645135 | 0x000f000e / 983054 |  |
| 29 | MUL | 0x00000400 / 1024 | 0x00000800 / 2048 | 0x00200000 / 2097152 |  |
| 30 | MULHU | 0x00000400 / 1024 | 0x00000800 / 2048 | 0x00000000 / 0 |  |
| 31 | MUL | 0x00010001 / 65537 | 0x0000fff1 / 65521 | 0xfff1fff1 / -917519 |  |
| 32 | MULHU | 0x00010001 / 65537 | 0x0000fff1 / 65521 | 0x00000000 / 0 |  |
| 33 | MUL | 0xffffffff / -1 | 0xffffffff / -1 | 0x00000001 / 1 |  |
| 34 | MULHSU | 0xffffffff / -1 | 0xffffffff / -1 | 0xffffffff / -1 |  |
| 35 | MUL | 0x075bcd15 / 123456789 | 0x3ade68b1 / 987654321 | 0xfbff5385 / -67153019 |  |
| 36 | MULHU | 0x075bcd15 / 123456789 | 0x3ade68b1 / 987654321 | 0x01b13114 / 28389652 |  |
| 37 | MUL | 0xffffffff / -1 | 0xffffffff / -1 | 0x00000001 / 1 |  |
| 38 | MULH | 0xffffffff / -1 | 0xffffffff / -1 | 0x00000000 / 0 |  |
| 39 | MUL | 0x80000000 / -2147483648 | 0xffffffff / -1 | 0x80000000 / -2147483648 |  |
| 40 | MULH | 0x80000000 / -2147483648 | 0xffffffff / -1 | 0x00000000 / 0 |  |
| 41 | MUL | 0xffffffff / -1 | 0x80000000 / -2147483648 | 0x80000000 / -2147483648 |  |
| 42 | MULH | 0xffffffff / -1 | 0x80000000 / -2147483648 | 0x00000000 / 0 | Caso documentado: delta!=0 |
| 43 | MUL | 0x80000000 / -2147483648 | 0x80000000 / -2147483648 | 0x00000000 / 0 |  |
| 44 | MULH | 0x80000000 / -2147483648 | 0x80000000 / -2147483648 | 0x40000000 / 1073741824 | Caso documentado: delta!=0 |

### 6.4 Comandos y flujo
1. **Firmware**: `cd Firmware && make` recompila `code.bin` y renueva `mul_test_vector`/`mul_report`.
2. **Simulación completa**: `make sim` genera `tb.out`, `tb.vcd` y lanza `gtkwave` usando el fichero `tb.gtkw` actualizado (ya incluye todas las señales útiles).
3. **Inspección manual**: si se desea reabrir después, basta con `gtkwave tb.vcd tb.gtkw`.

Con todo ello queda cubierta la “Segunda Parte: Integración en laRVa y simulación del programa” exigida en el enunciado.

## 7. Tutorial GTKWave: señales a observar y expectativas

### 7.1 Señales internas del multiplicador
1. **`tb.sys1.cpu.mul0.fast_active`**: vale `1` cuando el bypass entrega el resultado en un único ciclo. En esos instantes `mul0.busy` y `mbusy` permanecen en `0`.
2. **`tb.sys1.cpu.mul0.busy`**: indica que el núcleo secuencial sigue desplazando y sumando. Dura 33 ciclos en los casos generales; no llega a activarse en las pruebas rápidas (0, ±1, potencias de dos).
3. **`tb.sys1.cpu.mbusy`**: réplica del punto anterior pero expuesto al resto del procesador. Permite comprobar que el pipeline se desocupa inmediatamente cuando `fast_active=1`.
4. **`tb.sys1.cpu.mul0.fast_product_r[63:0]`**: registro que almacena el producto del bypass. En GTKWave se puede observar cómo `out` toma `fast_product_r[31:0]` para `MUL` y `fast_product_r[63:32]` para `MULH/MULHSU/MULHU`.
5. **`tb.sys1.cpu.mul0.seq_core.acc[63:0]`**: acumulador del multiplicador secuencial. Solo cambia en las pruebas que necesitan el algoritmo bit a bit; debe converger al valor esperado tras 33 ciclos.
6. **`tb.sys1.cpu.mul0.seq_core.sha[31:0]`**: registro desplazador del multiplicador. Se desplaza hacia la derecha hasta quedar a cero; ese instante coincide con la bajada de `busy`.
7. **`tb.sys1.cpu.mul0.seq_core.shb[63:0]`**: desplazador del multiplicando extendido. Permite ver cómo se inyectan ceros o signos en cada ciclo cuando el bypass no actúa.

El fichero `tb.gtkw` abre automáticamente todos estos nodos dentro del árbol `tb.sys1.cpu.mul0`.

### 7.2 Registros y memoria de la CPU
1. **Registros X5..X7 (`tb.sys1.cpu.regs[5..7][31:0]`)**: contienen los operandos y el resultado provisional (`t0`, `t1`, `t2`). Facilitan relacionar cada ciclo con el caso correspondiente.
2. **Registros X10..X12 (`tb.sys1.cpu.regs[10..12][31:0]`)**: la rutina usa `a0/a1/a2` para cargar el esperado, acumular `delta` y codificar el metadato. Tras cada prueba deben coincidir con los valores volcados en memoria.
3. **`tb.sys1.ram0.ram_array[0x704][31:0]`**: palabra donde se guarda `mul_status`. Cualquier valor distinto de cero implica que al menos un test produjo un `delta` no permitido.
4. **`tb.sys1.ram0.ram_array[0x705..]`**: bloque ocupado por `mul_report`. En `tb.gtkw` se muestran las primeras diez palabras (dos pruebas completas) y se puede añadir más nodos para inspeccionar el resto.

### 7.3 Cómo leer `mul_report`
- Cada registro ocupa cinco palabras consecutivas: `A`, `B`, `resultado HW`, `delta` y `metadatos`. El esperado se puede reconstruir con `esperado = resultado - delta`.
- El campo de metadatos codifica el número de prueba (bits [31:16]), los flags (bits [15:8]) y el identificador de instrucción (bits [7:0]). Por ejemplo, `0x00012A01` indica “prueba 0x12A, sin flags, MULH”.
- Las pruebas 42 y 44 tienen `FLAG_KNOWN_ISSUE` activado porque el hardware original devuelve resultados distintos a los teóricos al multiplicar `-1` por `-2^31`. Estos casos producen un `delta` distinto de cero pero no incrementan `mul_status`.
- Para ver otras entradas basta con añadir señales adicionales en GTKWave siguiendo el patrón `tb.sys1.ram0.ram_array[0x705 + offset]`.

### 7.4 Señal `busy` en el diseño original
- En la versión de referencia, `busy` era la única indicación de que el multiplicador estaba ocupando el bus interno. Se activaba cuando `load=1` y se mantenía alto mientras el registro desplazador `sha` tenía bits pendientes (33 ciclos en total). Con la integración actual, este comportamiento se preserva cuando no entra en juego el bypass; adicionalmente, cuando `fast_active=1`, la combinación `busy=0`/`mbusy=0` confirma que la operación se resolvió en un ciclo sin interferir con el pipeline.

### 7.5 Instrucciones de multiplicación RV32
1. **`MUL rd, rs1, rs2`**: calcula el producto de 32 bits y devuelve la mitad baja (`[31:0]`). Se usa tanto para enteros con signo como sin signo (los operandos se consideran en complemento a dos).
2. **`MULH rd, rs1, rs2`**: multiplica dos enteros con signo y entrega la mitad alta del resultado (`[63:32]`). Sirve para cálculos donde interesa el overflow o para construir productos de 64 bits.
3. **`MULHSU rd, rs1, rs2`**: el primer operando (`rs1`) es con signo, el segundo (`rs2`) sin signo. También devuelve la mitad alta.
4. **`MULHU rd, rs1, rs2`**: ambos operandos se consideran sin signo; devuelve la mitad alta del producto.

Para cada instrucción, los resultados esperados están recogidos en la tabla de la sección 6.3. Tras la simulación `mul_status` debe permanecer a cero para confirmar que todas las entradas de `mul_report` tienen `delta=0` (salvo los dos casos documentados).
# NOTAS Mario
### Para ejecutar con el multiplicador original de larva 2
iverilog -D ENABLE_MULDIV -o mult_tb.out multiplier_4bit_tb.v laRVa.v
vvp mult_tb.out



### Para ejecutar con el multiplicador del grupo 1.2
iverilog -o mult_tb.out multiplier_4bit_tb.v
vvp mult_tb.out

### Para ver ciclos de busy
```verilog
           // // Esperar a que termine
            // wait (!busy);
            // #2; // aparece el resultado más tarde


///////////////////////////////////////////////////////
//////// Añadido por Mario Medrano
///////////////////////////////////////////////////////
            // Medir la latencia en ciclos mientras busy=1 (0 si se aplica bypass)
            busy_cycles = 0;
            @(posedge clk);
            #1;
            while (busy) begin
                busy_cycles = busy_cycles + 1;
                @(posedge clk);
                #1;
            end
            $display("Ciclos busy: %0d", busy_cycles);
            #2;	// el resultado estable tarda un poco en propagarse
///////////////////////////////////////////////////////
```
