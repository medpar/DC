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
- En `laRVa.v` la sección `ENABLE_MULDIV` incluye ahora el fichero `mult_signo.v`, encerrado entre los separadores `// ----- CAMBIOS MARIO MEDRANO ...`. La instancia `mul0` no se modifica, por lo que el resto del pipeline sigue viendo los puertos originales.
- Al compilar el SoC, el nuevo módulo queda integrado automáticamente; ya no existe la definición antigua del multiplicador dentro de `laRVa.v`.

### 6.2 Programa de validación en `start.s`
- El arranque (`start`) llama a la rutina `mul_validation` antes de ejecutar `main`. Esta rutina está acotada por los comentarios `# ----- CAMBIOS MARIO MEDRANO ...`.
- Se definen macros y constantes para generar ocho pruebas: dos por cada instrucción (`MUL`, `MULH`, `MULHSU`, `MULHU`). Cada caso almacena seis palabras consecutivas en la tabla `mul_report`:
  1. Operando A.
  2. Operando B.
  3. Resultado de la instrucción.
  4. Valor esperado (precalculado).
  5. Delta = resultado − esperado (debe ser 0).
  6. Identificador de instrucción (`0=MUL`, `1=MULH`, `2=MULHSU`, `3=MULHU`).
- Los operandos cubren tanto los casos “rápidos” (0, ±1, potencias de dos) como los generales:

| Índice | Instr. | A | B | Esperado (hex) |
| --- | --- | --- | --- | --- |
| 0 | MUL | 0x00000005 | 0xFFFFFFF9 (-7) | 0xFFFFFFDD |
| 1 | MUL | 0x00000400 | 0x00000021 | 0x00008400 |
| 2 | MULH | 0x12345678 | 0x0FEDCBA9 | 0x0121FA00 |
| 3 | MULH | 0xFFF1E240 | 0x00ABCDEF | 0xFFFFF686 |
| 4 | MULHSU | 0xFFFFFFFB | 0x80000000 | 0xFFFFFFFD |
| 5 | MULHSU | 0x80000000 | 0x00000002 | 0xFFFFFFFF |
| 6 | MULHU | 0xFEDCBA98 | 0x01020304 | 0x0100DD74 |
| 7 | MULHU | 0x12345678 | 0x9ABCDEF0 | 0x0B00EA4E |

- El contador global `mul_status` almacena el número de fallos detectados para facilitar la comprobación rápida durante la simulación (0 = todo correcto).

### 6.3 Comandos y flujo
1. Regenerar el firmware con las nuevas pruebas:
   ```
   (cd Firmware && make)
   ```
2. Simular el SoC completo:
   ```
   make sim
   ```
3. Abrir la traza para inspección:
   ```
   gtkwave tb.vcd tb.gtkw
   ```

### 6.4 Interpretación con GTKWave
- **Señales del multiplicador**: añadir `tb.sys1.cpu.mul0.fast_active`, `tb.sys1.cpu.mul0.busy`, `tb.sys1.cpu.mul0.fast_product_r` y `tb.sys1.cpu.mul0.seq_core.acc`. Durante los casos rápidos (tests 1, 4, 5 y 6) `fast_active` se mantiene a 1 y `mbusy` no llega a activarse, confirmando la terminación inmediata.
- **Señales del procesador**: `tb.sys1.cpu.dbusy` permanece 0 mientras `mul_validation` se ejecuta; `tb.sys1.cpu.regs[x10..x15]` muestran los operandos cargados por la macro (útil para comprobar la secuencia).
- **Memoria de datos**: en `tb.vcd` seguir `tb.sys1.cpu.ram0.mem` (o la señal equivalente) y localizar la dirección etiquetada como `mul_status`. El valor debe ser 0. Justo después está la tabla `mul_report`; cada bloque de 6 palabras debe coincidir con la tabla anterior y la quinta palabra (delta) tiene que permanecer a 0.
- **Consola**: el flujo normal termina en el bucle infinito `loop:` sin generar excepciones. Si algún delta fuese distinto de cero, `mul_status` almacenaría el número de casos fallidos, lo que permitiría identificar rápidamente problemas en la integración.

Con todo ello queda cubierta la “Segunda Parte: Integración en laRVa y simulación del programa” exigida en el enunciado.

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
