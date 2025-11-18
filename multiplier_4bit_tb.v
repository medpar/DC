`timescale 1ns/1ps
`include "mult_signo.v"
module multiplier_4bit_tb;

    // Señales del DUT (Device Under Test)
    reg clk;
    reg reset;
    reg [31:0] a;
    reg [31:0] b;
    reg ua;
    reg ub;
    reg hm;
    reg load;
    wire busy;
    wire [31:0] out;
    
    // Variables auxiliares para verificación
    reg [63:0] resultado_esperado;
    reg [63:0] resultado_capturado;
    integer errores;
    integer pruebas;
    
    // Instanciar el DUT
//   multiplier_4bit_sequential DUT (
	multiplier DUT(		// Jesus Arias implementation
        .clk(clk),
        .reset(reset),
        .a(a),
        .b(b),
        .ua(ua),
        .ub(ub),
        .hm(hm),
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
        input unsigned_a;
        input unsigned_b;
        output [63:0] esperado;
        begin
            if (unsigned_a && unsigned_b) begin
                // Ambos sin signo
                esperado = op_a * op_b;
            end else if (!unsigned_a && !unsigned_b) begin
                // Ambos con signo
                esperado = {{32{op_a[31]}},op_a} * {{32{op_b[31]}},op_b};
 //               esperado = $signed(op_a) * $signed(op_b);
            end else if (!unsigned_a && unsigned_b) begin
                // a con signo, b sin signo
                esperado = {{32{op_a[31]}},op_a} * op_b;
            end else begin
                // a sin signo, b con signo
                esperado = op_a * {{32{op_b[31]}},op_b};
            end
        end
    endtask
    
    // Tarea para ejecutar una multiplicación
    task ejecutar_multiplicacion;
        input [31:0] op_a;
        input [31:0] op_b;
        input unsigned_a;
        input unsigned_b;
        input obtener_high;
        input [255:0] descripcion;
        begin
            $display("\n=== Prueba %0d: %0s ===", pruebas + 1, descripcion);
            $display("A = %d (0x%08h), B = %d (0x%08h)", 
                     unsigned_a ? op_a : $signed(op_a), op_a,
                     unsigned_b ? op_b : $signed(op_b), op_b);
            $display("UA = %b, UB = %b, HM = %b", unsigned_a, unsigned_b, obtener_high);
            
            // Configurar operación
            a = op_a;
            b = op_b;
            ua = unsigned_a;
            ub = unsigned_b;
            hm = obtener_high;
            
            // Calcular resultado esperado
            calcular_esperado(op_a, op_b, unsigned_a, unsigned_b, resultado_esperado);
            
            // Iniciar multiplicación
            #2 load = 1;
            #10 load = 0;

            // Esperar a que termine
            wait (!busy);
			#2;	// aparece el resultado más tarde

            // Capturar resultado de palabra baja
            if (!obtener_high) begin
                resultado_capturado = out;
                $display("Resultado (low): 0x%08h", out);
                $display("Esperado  (low): 0x%08h", resultado_esperado[31:0]);
                
                if (out !== resultado_esperado[31:0]) begin
                    $display("ERROR: Resultado incorrecto en palabra baja!");
                    errores = errores + 1;
                end else begin
                    $display("CORRECTO: Palabra baja");
                end
            end
            
            // Para verificar palabra alta, ejecutar de nuevo con hm=1
            if (obtener_high) begin
                // Siempre verificar palabra alta

//               while (busy);
                resultado_capturado = out;             
                $display("Resultado (high): 0x%08h", out);
                $display("Esperado  (high): 0x%08h", resultado_esperado[63:32]);
                
                if (out !== resultado_esperado[63:32]) begin
                    $display("ERROR: Resultado incorrecto en palabra alta!");
                    errores = errores + 1;
                end else begin
                    $display("CORRECTO: Palabra alta");
                end
            end
            
            pruebas = pruebas + 1;
            @(posedge clk);
        end
    endtask
    
    // Programa principal de pruebas
    initial begin
        // Inicialización
        $dumpfile("multiplier_4bit_tb.vcd");
        $dumpvars(0, multiplier_4bit_tb);
        
        errores = 0;
        pruebas = 0;
        reset = 1;
        a = 0;
        b = 0;
        ua = 0;
        ub = 0;
        hm = 0;
        load = 0;
        
        // Reset del sistema
        #20 reset = 0;
        @(posedge clk);
        
        $display("\n========================================");
        $display("  INICIO DE PRUEBAS DEL MULTIPLICADOR");
        $display("========================================");
        // PRUEBA 1: Números pequeños positivos (parte baja)
        ejecutar_multiplicacion(32'd5, 32'd7, 1, 1, 0, "Num bajos ++ (5 x 7) low");
        // PRUEBA 2: Números pequeños positivos (parte alta)
        ejecutar_multiplicacion(32'd5, 32'd7, 1, 1, 1, "Num bajos ++ (5 x 7) high");
        // PRUEBA 3: Números pequeños con diferente signo (parte baja)
        ejecutar_multiplicacion(32'd5, -32'd7, 1, 0, 0, "Num bajos +- (5 x -7) low");
        // PRUEBA 4: Números pequeños con diferente signo (parte alta)
        ejecutar_multiplicacion(32'd5, -32'd7, 1, 0, 1, "Num bajos +- (5 x -7) high");
        // PRUEBA 5: Números pequeños con diferente signo (parte baja)
        ejecutar_multiplicacion(-32'd5, 32'd7, 0, 0, 0, "Num bajos -+ (-5 x 7) low");
        // PRUEBA 6: Números pequeños con diferente signo (parte alta)
        ejecutar_multiplicacion(-32'd5, 32'd7, 0, 0, 1, "Num bajos -+ (-5 x 7) high");
        // PRUEBA 7: Números pequeños ambos negativos
        ejecutar_multiplicacion(-32'd5, -32'd7, 0, 0, 0, "Num bajos -- (-5 x -7) low");
        // PRUEBA 8: Números pequeños ambos negativos
        ejecutar_multiplicacion(-32'd5, -32'd7, 0, 0, 1, "Num bajos -- (-5 x -7) high");
        
        // PRUEBA 9: Multiplicación por cero
        ejecutar_multiplicacion(32'd12345, 32'd0, 1, 1, 0, "Multando = 0 low");
        // PRUEBA 10: Multiplicación por cero
        ejecutar_multiplicacion(32'd12345, 32'd0, 1, 1, 1, "Multando = 0 high");
        // PRUEBA 11: Multiplicación por cero
        ejecutar_multiplicacion(32'd0, 32'd12345, 1, 1, 0, "Mulor = 0 low");
        // PRUEBA 12: Multiplicación por cero
        ejecutar_multiplicacion(32'd0, 32'd12345, 1, 1, 1, "Mulor = 0 high");
        
        // PRUEBA 13: Multiplicación por uno
        ejecutar_multiplicacion(32'd12345, 32'd1, 1, 1, 0, "Multiplicacion por 1 low");
        // PRUEBA 14: Multiplicación por uno
        ejecutar_multiplicacion(32'd12345, 32'd1, 1, 1, 1, "Multiplicacion por 1 high");
        // PRUEBA 15: Multiplicación por -1
        ejecutar_multiplicacion(32'd12345, -32'd1, 1, 0, 0, "Multiplicacion por -1 low");
        // PRUEBA 16: Multiplicación por -1
        ejecutar_multiplicacion(32'd12345, -32'd1, 1, 0, 1, "Multiplicacion por -1 high");
        
        // PRUEBA 17: Números muy grandes sin signo
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'hFFFFFFFF, 1, 1, 0, 
                              "altos unsigned (2^32-1 x 2^32-1) low");
        // PRUEBA 18: Números muy grandes sin signo
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'hFFFFFFFF, 1, 1, 1, 
                              "altos unsigned (2^32-1 x 2^32-1) high");
        
        // PRUEBA 19: Números grandes con signo positivo
        ejecutar_multiplicacion(32'h7FFFFFFF, 32'h7FFFFFFF, 0, 0, 0, 
                              "altos signed + (2^31-1 x 2^31-1) low");
        // PRUEBA 20: Números grandes con signo positivo
        ejecutar_multiplicacion(32'h7FFFFFFF, 32'h7FFFFFFF, 0, 0, 1, 
                              "altos signed + (2^31-1 x 2^31-1) high");
        
        // PRUEBA 21: Números grandes con diferente signo
        ejecutar_multiplicacion(32'h7FFFFFFF, 32'h80000000, 0, 0, 0, 
                              "grande signo + x grande signo low");
        // PRUEBA 22: Números grandes con diferente signo
        ejecutar_multiplicacion(32'h7FFFFFFF, 32'h80000000, 0, 0, 1, 
                              "grande signo + x grande signo high");
        
        // PRUEBA 23: Casos de overflow intermedio
       ejecutar_multiplicacion(32'h10000, 32'h10000, 1, 1, 0, 
                              "65536 x 65536 (overflow a palabra alta) low");
        // PRUEBA 24: Casos de overflow intermedio
       ejecutar_multiplicacion(32'h10000, 32'h10000, 1, 1, 1, 
                              "65536 x 65536 (overflow a palabra alta) high");
        
        // PRUEBA 25: Patrones de bits especiales
        ejecutar_multiplicacion(32'h55555555, 32'hAAAAAAAA, 1, 1, 0, 
                              "signed (0x5555... x 0xAAAA...) low");
        // PRUEBA 26: Patrones de bits especiales
        ejecutar_multiplicacion(32'h55555555, 32'hAAAAAAAA, 1, 1, 1, 
                              "signed (0x5555... x 0xAAAA...) high");
        
        // PRUEBA 27: Números con muchos ceros en nibbles
        ejecutar_multiplicacion(32'h00FF00FF, 32'h0F0F0F0F, 1, 1, 0, 
                              "Numeros con nibbles cero low");
        // PRUEBA 28: Números con muchos ceros en nibbles
        ejecutar_multiplicacion(32'h00FF00FF, 32'h0F0F0F0F, 1, 1, 1, 
                              "Numeros con nibbles cero high");
        
        // PRUEBA 29: Potencias de 2
        ejecutar_multiplicacion(32'd1024, 32'd2048, 1, 1, 0, 
                              "Potencias de 2 (1024 x 2048)low");
        // PRUEBA 30: Potencias de 2
        ejecutar_multiplicacion(32'd1024, 32'd2048, 1, 1, 1, 
                              "Potencias de 2 (1024 x 2048)high");
        
        // PRUEBA 31: Números primos grandes
        ejecutar_multiplicacion(32'd65537, 32'd65521, 1, 1, 0, 
                              "Numeros primos grandes low");
        // PRUEBA 32: Números primos grandes
        ejecutar_multiplicacion(32'd65537, 32'd65521, 1, 1, 1, 
                              "Numeros primos grandes high");

        // PRUEBA 33: Maximo sin signo x -1       
        ejecutar_multiplicacion(32'hFFFFFFFF, -32'd1, 1, 0, 0, 
                              "Maximo sin signo x -1 low");
        // PRUEBA 34: Maximo sin signo x -1       
        ejecutar_multiplicacion(32'hFFFFFFFF, -32'd1, 1, 0, 1, 
                              "Maximo sin signo x -1 high");
        
        // PRUEBA 35: Números aleatorios
        ejecutar_multiplicacion(32'd123456789, 32'd987654321, 1, 1, 0, 
                              "Numeros aleatorios grandes low");
        // PRUEBA 36: Números aleatorios
        ejecutar_multiplicacion(32'd123456789, 32'd987654321, 1, 1, 1, 
                              "Numeros aleatorios grandes high");
        
        // PRUEBA 37: Caso especial -1 x -1
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'hFFFFFFFF, 0, 0, 0, 
                              "(-1) x (-1) con signo, low");
        // PRUEBA 38: Caso especial -1 x -1
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'hFFFFFFFF, 0, 0, 1, 
                              "(-1) x (-1) con signo, high");

        // PRUEBA 39: Número maximo con signo negativo en A
        ejecutar_multiplicacion(32'h80000000, 32'hFFFFFFFF, 0, 0, 0, 
                              "max signed - (-2^31-1 x -1) low");
        // PRUEBA 40: Número maximo con signo negativo en A
        ejecutar_multiplicacion(32'h80000000, 32'hFFFFFFFF, 0, 0, 1, 
                              "max signed - (-2^31-1 x -1) high");
        
        // PRUEBA 41: Número maximo con signo negativo en B
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'h80000000, 0, 0, 0, 
                              "max signed - (-1 x -2^31-1) low");
        // PRUEBA 42: Número maximo con signo negativo en B
        ejecutar_multiplicacion(32'hFFFFFFFF, 32'h80000000, 0, 0, 1, 
                              "max signed - (-1 x -2^31-1) high");
        
        // PRUEBA 43: Números max con signo negativo
        ejecutar_multiplicacion(32'h80000000, 32'h80000000, 0, 0, 0, 
                              "max signo - (-2^31 x -2^31) low");
        // PRUEBA 44: Números max con signo negativo
        ejecutar_multiplicacion(32'h80000000, 32'h80000000, 0, 0, 1, 
                              "max signo - (-2^31 x -2^31) high");
        

        
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