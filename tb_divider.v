`timescale 1ns/1ps
`include "divider.v"
module tb_divider;

    // Señales del DUT (Device Under Test)
    reg clk;
    reg reset;
    reg [31:0] a;
    reg [31:0] b;
    reg unsig;
    reg rem;
    reg load;
    wire busy;
    wire [31:0] out;
    
    // Variables auxiliares para verificación
    reg [31:0] resultado_esperado;
    reg [31:0] resultado_capturado;
    integer errores;
    integer pruebas;

    // Instanciar el DUT
   divider DUT (
        .clk(clk),
        .reset(reset),
        .a(a),
        .b(b),
        .unsig(unsig),
        .rem(rem),
        .load(load),
        .busy(busy),
        .out(out)
    );
    
    // Generador de reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // Periodo de 10ns
    end
    
    // Tareas auxiliares
    
    // Tarea para calcular resultado esperado
    task calcular_esperado;
        input [31:0] op_a;
        input [31:0] op_b;
        input unsig;
        input rem;
        output [31:0] esperado;
		
		integer na, ma, nb, mb, esperado_abs, oneg;
		
        begin
			a = op_a;
			b = op_b;
            if (unsig & !rem) begin
                // Ambos sin signo - cociente
                esperado = op_a / op_b;
            end else if (unsig & rem) begin
                // Ambos sin signo - resto
                esperado = op_a % op_b;
            end else if (!unsig && !rem) begin
                // ambos con signo - cociente
					// make operands positive
					 ma = op_a[31] ? ((~op_a)+1) : op_a;
					 mb = op_b[31] ? ((~op_b)+1) : op_b;
				// divide abs
				esperado_abs = ma / mb;
				// sign result correction
				oneg = (op_a[31]^op_b[31]);
				esperado = oneg ? (~esperado_abs+1) : esperado_abs;
			
            end else begin
				esperado = a % b;
                // ambos con signo - resto
					// make operands positive
					 ma = op_a[31] ? ((~op_a)+1) : op_a;
					 mb = op_b[31] ? ((~op_b)+1) : op_b;
				// divide abs - remainder
				esperado_abs = ma % mb;
				// sign result correction
				oneg = (op_a[31]^op_b[31]);
				esperado = oneg ? (~esperado_abs+1) : esperado_abs ;
            end
        end
    endtask
    
    // Tarea para ejecutar una division
    task ejecutar_division;
        input [31:0] op_a;
        input [31:0] op_b;
        input unsign;
        input obtener_remain;
        input [255:0] descripcion;
        begin
            $display("\n== Prueba %0d: %0s ==", pruebas + 1, descripcion);
            $display("A = %d (0x%08h), B = %d (0x%08h)", 
                     unsign ? op_a : $signed(op_a), op_a,
                     unsign ? op_b : $signed(op_b), op_b);
            $display("Unsigned = %b,  RESTO = %b", unsign, obtener_remain);
            
            // Configurar operación
            a = op_a;
            b = op_b;
            unsig = unsign;
            rem = obtener_remain;
            
            // Calcular resultado esperado
            calcular_esperado(op_a, op_b, unsign, obtener_remain, resultado_esperado);
            
            // Iniciar multiplicación
            #2 load = 1;
            #10 load = 0;

            // Esperar a que termine
            wait (!busy);
			#2;
            // Capturar resultado
                resultado_capturado = out;
                $display("Resultado: 0x%08h", out);
                $display("Esperado:  0x%08h", resultado_esperado[31:0]);
                
                if (out !== resultado_esperado[31:0]) begin
                    $display("ERROR: Resultado incorrecto");
                    errores = errores + 1;
                end else begin
                    $display("CORRECTO");
                end
                        
            pruebas = pruebas + 1;
            @(posedge clk);
        end
    endtask
    
    // Programa principal de pruebas
    initial begin
        // Inicialización
        $dumpfile("divider_tb.vcd");
        $dumpvars(0, tb_divider);
        
        errores = 0;
        pruebas = 0;
        reset = 1;
        a = 0;
        b = 0;
        unsig = 0;
        rem = 0;
        load = 0;
        
        // Reset del sistema
        #20 reset = 0;
        @(posedge clk);
        
        $display("\n========================================");
        $display("  TESTBENCH DEL DIVISOR - 32 BITS");
        $display("========================================");
        
        // ===== CASOS TIPICOS =====
        $display("\n----- CASOS TIPICOS -----");
        
        // Divisiones exactas básicas
        ejecutar_division(32'd100, 32'd10, 1, 0, "Div exacta: 100/10 (cociente)");
        ejecutar_division(32'd100, 32'd10, 1, 1, "Div exacta: 100/10 (resto)");
        
        // Divisiones con resto
        ejecutar_division(32'd100, 32'd7, 1, 0, "Div con resto: 100/7 (cociente)");
        ejecutar_division(32'd100, 32'd7, 1, 1, "Div con resto: 100/7 (resto)");
        
        // División por 1
        ejecutar_division(32'd12345, 32'd1, 1, 0, "Div entre 1: 12345/1 (cociente)");
        ejecutar_division(32'd12345, 32'd1, 1, 1, "Div entre 1: 12345/1 (resto)");
        
        // División de un número por sí mismo
        ejecutar_division(32'd999, 32'd999, 1, 0, "Div identica: 999/999 (cociente)");
        ejecutar_division(32'd999, 32'd999, 1, 1, "Div identica: 999/999 (resto)");
        
        // Dividendo menor que divisor
        ejecutar_division(32'd5, 32'd10, 1, 0, "Dividendo<divisor: 5/10 (cociente)");
        ejecutar_division(32'd5, 32'd10, 1, 1, "Dividendo<divisor: 5/10 (resto)");
        
        // División de cero
        ejecutar_division(32'd0, 32'd100, 1, 0, "Cero en dividendo: 0/100 (cociente)");
        ejecutar_division(32'd0, 32'd100, 1, 1, "Cero en dividendo: 0/100 (resto)");
        
        // Potencias de 2
        ejecutar_division(32'd1024, 32'd16, 1, 0, "Pot 2: 1024/16 (cociente)");
        ejecutar_division(32'd1024, 32'd16, 1, 1, "Pot 2: 1024/16 (resto)");
        
        // ===== CASOS CON SIGNO TIPICOS =====
        $display("\n----- CASOS CON SIGNO TIPICOS -----");
        
        // Ambos positivos
        ejecutar_division(32'd100, 32'd7, 0, 0, "Ambos pos: 100/7 (cociente)");
        ejecutar_division(32'd100, 32'd7, 0, 1, "Ambos pos: 100/7 (resto)");
        
        // Dividendo negativo, divisor positivo
        ejecutar_division(-32'd100, 32'd7, 0, 0, "Neg/Pos: -100/7 (cociente)");
        ejecutar_division(-32'd100, 32'd7, 0, 1, "Neg/Pos: -100/7 (resto)");
        
        // Dividendo positivo, divisor negativo
        ejecutar_division(32'd100, -32'd7, 0, 0, "Pos/Neg: 100/-7 (cociente)");
        ejecutar_division(32'd100, -32'd7, 0, 1, "Pos/Neg: 100/-7 (resto)");
        
        // Ambos negativos
        ejecutar_division(-32'd100, -32'd7, 0, 0, "Ambos neg: -100/-7 (cociente)");
        ejecutar_division(-32'd100, -32'd7, 0, 1, "Ambos neg: -100/-7 (resto)");
        
        // División por -1
        ejecutar_division(32'd12345, -32'd1, 0, 0, "Div entre -1: 12345/-1 (cociente)");
        ejecutar_division(32'd12345, -32'd1, 0, 1, "Div entre -1: 12345/-1 (resto)");
        
        // ===== CASOS PROBLEMÁTICOS =====
        $display("\n----- CASOS PROBLEMATICOS -----");
        
        // CRÍTICO: División por cero -  pruebas 25-28
        ejecutar_division(32'd12345, 32'd0, 1, 0, "CRITICO: Divisor 0 unsign (cociente)");
        ejecutar_division(32'd12345, 32'd0, 1, 1, "CRITICO: Divisor 0 unsign (resto)");
        ejecutar_division(-32'd100, 32'd0, 0, 0, "CRITICO: Divisor 0 sign (cociente)");
        ejecutar_division(-32'd100, 32'd0, 0, 1, "CRITICO: Divisor 0 sign (resto)");
        // División de 0 entre 0 - pruebas 29, 30
        ejecutar_division(32'h00000000, 32'h00000000, 1, 0, "division 0/0");
        ejecutar_division(32'h00000000, 32'h00000000, 1, 1, "division 0/0");
        
        
        // CRÍTICO: Overflow en división con signo (-2^31 / -1) -  pruebas 31, 32
        ejecutar_division(32'h80000000, -32'd1, 0, 0, "CRITICO: Ovflow -2^31/-1 (coc)");
        ejecutar_division(32'h80000000, -32'd1, 0, 1, "CRITICO: Ovflow -2^31/-1 (resto)");
        
        // Valores máximos sin signo -  pruebas 33, 34
        ejecutar_division(32'hFFFFFFFF, 32'd2, 1, 0, "Max unsign: 2^32-1 / 2 (coc)");
        ejecutar_division(32'hFFFFFFFF, 32'd2, 1, 1, "Max unsign: 2^32-1 / 2 (resto)");
        
        // División de máximos valores sin signo - pruebas 35, 36
        ejecutar_division(32'hFFFFFFFF, 32'hFFFFFFFF, 1, 0, "Maxs unsign: 2^32-1 / 2^32-1 (cociente)");
        ejecutar_division(32'hFFFFFFFF, 32'hFFFFFFFF, 1, 1, "Maxs unsign: 2^32-1 / 2^32-1 (resto)");
        
        // Máximo positivo con signo - pruebas 37, 38
        ejecutar_division(32'h7FFFFFFF, 32'd2, 0, 0, "Max +: 2^31-1 / 2 (cociente)");
        ejecutar_division(32'h7FFFFFFF, 32'd2, 0, 1, "Max +: 2^31-1 / 2 (resto)");
        
        // Mínimo negativo con signo (excepto overflow ya probado) - pruebas 39, 40
        ejecutar_division(32'h80000000, 32'd2, 0, 0, "Min -: -2^31 / 2 (cociente)");
        ejecutar_division(32'h80000000, 32'd2, 0, 1, "Min -: -2^31 / 2 (resto)");
        
        // División entre -1 y -1 - pruebas 41, 42
        ejecutar_division(-32'd1, -32'd1, 0, 0, "Especial: -1/-1 (cociente)");
        ejecutar_division(-32'd1, -32'd1, 0, 1, "Especial: -1/-1 (resto)");
        
        // Patrones de bits alternados - pruebas 43, 44
        ejecutar_division(32'hAAAAAAAA, 32'h55555555, 1, 0, "0xAAAA../0x5555.. (cociente)");
        ejecutar_division(32'hAAAAAAAA, 32'h55555555, 1, 1, "0xAAAA../0x5555.. (resto)");
                
        // Números primos grandes - pruebas 45, 46
        ejecutar_division(32'd65537, 32'd257, 1, 0, "Primos big: 65537/257 (cociente)");
        ejecutar_division(32'd65537, 32'd257, 1, 1, "Primos big: 65537/257 (resto)");
        
        // Valor máximo dividido entre valor mínimo (con signo) - pruebas 47, 48
        ejecutar_division(32'h7FFFFFFF, 32'h80000000, 0, 0, "Max pos / Min neg (cociente)");
        ejecutar_division(32'h7FFFFFFF, 32'h80000000, 0, 1, "Max pos / Min neg (resto)");
        
        // Casos con divisor = 1 bit activo - pruebas 49, 50
        ejecutar_division(32'hF0F0F0F0, 32'd16, 1, 0, "Divisor pot de 2: /16 (cociente)");
        ejecutar_division(32'hF0F0F0F0, 32'd16, 1, 1, "Divisor pot de 2: /16 (resto)");
        
        // Números grandes aleatorios - pruebas 51, 52
        ejecutar_division(32'd987654321, 32'd123456, 1, 0, "Num big unsign: 987654321/123456 (coc)");
        ejecutar_division(32'd987654321, 32'd123456, 1, 1, "Num big unsign: 987654321/123456 (resto)");
        
        // Divisiones casi exactas - pruebas 53, 54
        ejecutar_division(32'd1000000, 32'd3, 1, 0, "Div casi exact unsign: 1000000/3 (coc)");
        ejecutar_division(32'd1000000, 32'd3, 1, 1, "Div casi exact unsign: 1000000/3 (resto)");
        
        // ===== CASOS ADICIONALES DE ESTRÉS =====
        $display("\n----- CASOS DE ESTRES ADICIONALES -----");
        
        // Máximo valor sin signo dividido entre 1  - pruebas 55, 56
        ejecutar_division(32'hFFFFFFFF, 32'd1, 1, 0, "Estres: Max/1 sin signo (cociente)");
        ejecutar_division(32'hFFFFFFFF, 32'd1, 1, 1, "Estres: Max/1 sin signo (resto)");
        
        // Mínimo con signo dividido entre máximo con signo - pruebas 57, 58
        ejecutar_division(32'h80000000, 32'h7FFFFFFF, 0, 0, "Estres: Min/Max con signo (cociente)");
        ejecutar_division(32'h80000000, 32'h7FFFFFFF, 0, 1, "Estres: Min/Max con signo (resto)");
        
        // División donde resultado es casi el dividendo - pruebas 59, 60
        ejecutar_division(32'hFFFFFFF0, 32'hFFFFFFFF, 1, 0, "Estres: Numeros muy cercanos (cociente)");
        ejecutar_division(32'hFFFFFFF0, 32'hFFFFFFFF, 1, 1, "Estres: Numeros muy cercanos (resto)");
        
        
        // Resumen final
        $display("\n========================================");
        $display("  RESUMEN DE PRUEBAS");
        $display("========================================");
        $display("Total de pruebas ejecutadas: %0d", pruebas);
        $display("Errores encontrados: %0d", errores);
        if (errores == 0) begin
            $display("¡TODAS LAS PRUEBAS PASARON EXITOSAMENTE!");
        end else begin
            $display("ATENCION: Se encontraron errores en las pruebas");
        end
        $display("========================================\n");
        
        // Esperar un poco antes de terminar
        #100;
        $finish;
    end
    
/*    // Monitor para debugging
    initial begin
        $monitor("Tiempo=%0t, Estado: reset=%b, load=%b, busy=%b, ciclo_actual=%d", 
                 $time, reset, load, busy, DUT.ciclo_count);
    end
*/

endmodule