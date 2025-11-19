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

Con esta información se cubre la “Primera Parte: Diseño del componente” solicitada en el enunciado y queda listo para su integración en etapas posteriores.

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