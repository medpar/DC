//------------------------------------------------------------------------------
// Multiplicador con bypass para laRVa (Primera parte del proyecto)
// Mantiene la interfaz original para ser intercambiable con el núcleo existente.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

module multiplier (
    input        clk,
    input        reset,
    input  [31:0]a,
    input  [31:0]b,
    input        ua,
    input        ub,
    input        hm,
    input        load,
    output       busy,
    output [31:0]out
);

    //--------------------------------------------------------------------------
    // Transformaciones de entrada: extensión de signo y módulo absoluto
    //--------------------------------------------------------------------------
    // Extensiones a 64 bits según el tratamiento con o sin signo. Se trabaja a
    // 64 bits porque el resultado del multiplicador ocupa ese ancho y así no
    // hay pérdida de información en el camino rápido.
    wire signed [63:0] a_ext = ua ? $signed({32'b0, a}) : $signed({{32{a[31]}}, a});
    wire signed [63:0] b_ext = ub ? $signed({32'b0, b}) : $signed({{32{b[31]}}, b});

    // Módulos absolutos para detectar potencias de dos (se usan valores
    // positivos porque en las potencias negativas solo cambia el signo final).
    wire [31:0] a_abs = (~ua & a[31]) ? (~a + 32'd1) : a;
    wire [31:0] b_abs = (~ub & b[31]) ? (~b + 32'd1) : b;

    //--------------------------------------------------------------------------
    // Detección de casos triviales
    //--------------------------------------------------------------------------
    // Cada una de estas banderas activa el camino rápido y evita la iteración
    // de 33 ciclos del multiplicador secuencial clásico.
    wire a_zero = (a == 32'd0);
    wire b_zero = (b == 32'd0);
    wire a_pos_one = (a == 32'd1);
    wire b_pos_one = (b == 32'd1);
    // en modo firmado, el valor 0xFFFF_FFFF equivale a -1, por eso se añade la
    // condición (~u?) que asegura que el operando se esté tratando con signo.
    wire a_neg_one = (~ua) & (a == 32'hFFFF_FFFF);
    wire b_neg_one = (~ub) & (b == 32'hFFFF_FFFF);

    // Potencias de dos (en valor absoluto). Se clona la lógica de detección
    // típica value & (value - 1) == 0 para evitar recurrir a módulos costosos.
    wire a_pow2 = (a_abs != 0) && ((a_abs & (a_abs - 1)) == 0);
    wire b_pow2 = (b_abs != 0) && ((b_abs & (b_abs - 1)) == 0);

    // Índice del bit a 1 usado para calcular el desplazamiento en potencias de dos
    // El bucle for recorre todos los bits y guarda la última posición en la que
    // encuentra un '1'. Para potencias de dos solo habrá un bit activo, por lo
    // que el resultado será el desplazamiento exacto.
    function automatic [5:0] bit_index32;
        input [31:0] value;
        integer idx;
        begin
            bit_index32 = 6'd0;
            for (idx = 0; idx < 32; idx = idx + 1)
                if (value[idx]) bit_index32 = idx[5:0];
        end
    endfunction

    wire [5:0] a_shift = bit_index32(a_abs);
    wire [5:0] b_shift = bit_index32(b_abs);

    wire a_neg = (~ua) & a[31];
    wire b_neg = (~ub) & b[31];

    //--------------------------------------------------------------------------
    // Camino rápido combinacional
    //--------------------------------------------------------------------------
    // Si 'fast_valid_c' es 1, el secuencial se inhibe y se devuelve el valor
    // calculado en 'fast_product_c'. Así se obtiene el resultado en un solo ciclo.
    reg        fast_valid_c;
    reg signed [63:0] fast_product_c;

    always @(*) begin
        fast_valid_c   = 1'b0;
        fast_product_c = 64'sd0;

        // Los casos se evalúan con prioridad. En cuanto se detecta uno válido
        // se calcula el producto correspondiente y se marca como disponible.
        if (a_zero || b_zero) begin
            fast_valid_c   = 1'b1;
            fast_product_c = 64'sd0;
        end else if (a_pos_one) begin
            fast_valid_c   = 1'b1;
            fast_product_c = b_ext;
        end else if (b_pos_one) begin
            fast_valid_c   = 1'b1;
            fast_product_c = a_ext;
        end else if (a_neg_one) begin
            fast_valid_c   = 1'b1;
            fast_product_c = -b_ext;
        end else if (b_neg_one) begin
            fast_valid_c   = 1'b1;
            fast_product_c = -a_ext;
        end else if (a_pow2) begin
            fast_valid_c   = 1'b1;
            fast_product_c = a_neg ? -(b_ext <<< a_shift) : (b_ext <<< a_shift);
        end else if (b_pow2) begin
            fast_valid_c   = 1'b1;
            fast_product_c = b_neg ? -(a_ext <<< b_shift) : (a_ext <<< b_shift);
        end
    end

    //--------------------------------------------------------------------------
    // Registros para conservar el resultado inmediato
    //--------------------------------------------------------------------------
    // 'fast_active' recuerda que la última operación se resolvió por bypass.
    // 'fast_product_r' guarda el resultado para que pueda leerse su parte alta
    // o baja cuando sea necesario (por ejemplo tras cambiar hm).
    reg        fast_active;
    reg signed [63:0] fast_product_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fast_active    <= 1'b0;
            fast_product_r <= 64'sd0;
        end else if (load) begin
            fast_active    <= fast_valid_c;
            if (fast_valid_c) fast_product_r <= fast_product_c;
        end
    end

    // Cuando 'fast_valid_c' es 0 el kernel secuencial procesa la operación
    // exactamente igual que el multiplicador original de laRVa.
    // Núcleo secuencial original para los casos generales
    wire        seq_busy;
    wire [31:0] seq_out;

    multiplier_seq seq_core (
        .clk  (clk),
        .reset(reset),
        .a    (a),
        .b    (b),
        .ua   (ua),
        .ub   (ub),
        .hm   (hm),
        .load (load & ~fast_valid_c),  // si hay bypass, el núcleo secuencial no se activa
        .busy (seq_busy),
        .out  (seq_out)
    );

    // Salidas de la ruta rápida. Se reutilizan cuando 'hm' cambia; de esta forma
    // una misma operación sirve para MUL y MULH si se solicitan de manera
    // consecutiva.
    wire [31:0] fast_low  = fast_product_r[31:0];
    wire [31:0] fast_high = fast_product_r[63:32];

    // Multiplexores finales. Cuando el camino rápido tuvo éxito se ignora el
    // 'busy' secuencial y se entrega directamente el resultado almacenado.
    assign busy = fast_active ? 1'b0 : seq_busy;
    assign out  = fast_active ? (hm ? fast_high : fast_low) : seq_out;

endmodule

//------------------------------------------------------------------------------
// Núcleo secuencial original renombrado (idéntico al de laRVa.v)
// Este bloque se mantiene sin cambios funcionales para garantizar que el
// procesador sigue viendo la misma temporización cuando no aplica el bypass.
//------------------------------------------------------------------------------
module multiplier_seq (
    input        clk,
    input        reset,
    input  [31:0]a,
    input  [31:0]b,
    input        ua,
    input        ub,
    input        hm,
    input        load,
    output       busy,
    output [31:0]out
);

    // Banco de registros interno que almacena los operandos y su modo de signo.
    // Esto permite detectar cuándo se repite la misma multiplicación y reutilizar
    // el resultado sin reactivar la máquina de estados.
    reg [31:0] oa;
    reg [31:0] ob;
    reg        oua;
    reg        oub;
    always @(posedge clk or posedge reset) begin
        if (reset) {oua, oa} <= 0;
        else if (load) {oua, oa} <= {ua, a};
    end
    always @(posedge clk or posedge reset) begin
        if (reset) {oub, ob} <= 0;
        else if (load) {oub, ob} <= {ub, b};
    end

    wire iload = load & (({oa, ob} != {a, b}) | (hm & ({oua, oub} != {ua, ub})));

    // Ajuste de signo de entrada. 'sma' indica si el multiplicador es negativo
    // en modo firmado. Si lo es, se invierten ambos operandos para que la parte
    // secuencial trabaje solo con magnitudes positivas.
    wire        sma = (~ua) & a[31];
    wire [31:0] ma  = (sma ? (~a) : a) + sma;
    wire [31:0] mb  = (sma ? (~b) : b) + sma;

    // Registro desplazador del multiplicador. Cada ciclo desplaza un bit hacia
    // la derecha y sirve de contador de los 32 pasos necesarios.
    reg [31:0] sha = 0;
    always @(posedge clk or posedge reset) begin
        if (reset) sha <= 0;
        else sha <= iload ? ma : {1'b0, sha[31:1]};
    end
    // 'busy' permanece activo mientras exista algún bit pendiente en el
    // desplazador o mientras se está cargando una nueva operación.
    assign busy = iload | (|sha);

    // Registro desplazador del multiplicando extendido a 64 bits. Su LSB se
    // suma al acumulador cuando el bit actual del multiplicador es 1.
    reg [63:0] shb;
    always @(posedge clk)
        shb <= iload ? (ub ? {32'b0, mb} : {{32{mb[31]}}, mb}) : {shb[62:0], 1'b0};

    // Acumulador: almacena la suma parcial de los productos desplazados, igual
    // que en el diseño original. Cuando 'iload' es 1 se reinicia a cero.
    reg [63:0] acc;
    always @(posedge clk or posedge reset) begin
        if (reset) acc <= 0;
        else if (iload | sha[0]) acc <= iload ? 64'd0 : acc + shb;
    end

    // Selección de palabra alta/baja del acumulador, sin cambios respecto a laRVa.
    assign out = hm ? acc[63:32] : acc[31:0];
endmodule
