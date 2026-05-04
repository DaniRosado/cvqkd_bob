`timescale 1ns / 1ps

module tb_final_math_unit();

    // Señales
    logic clk;
    logic rst;
    logic start_calc;
    
    logic signed [63:0] sum_sq_P_B, sum_P_B, sum_cov_P, sum_P_A;
    logic signed [63:0] sum_sq_Q_B, sum_Q_B, sum_cov_Q, sum_Q_A;
    
    logic signed [31:0] calib_N0, calib_Velec, calib_VarA, calib_eta;
    
    logic signed [31:0] T_final, xi_final;
    logic data_ready;

    // Instancia del Súper Bloque
    final_math_unit dut (
        .clk(clk), .rst(rst), .start_calc(start_calc),
        .sum_sq_P_B(sum_sq_P_B), .sum_P_B(sum_P_B), .sum_cov_P(sum_cov_P), .sum_P_A(sum_P_A),
        .sum_sq_Q_B(sum_sq_Q_B), .sum_Q_B(sum_Q_B), .sum_cov_Q(sum_cov_Q), .sum_Q_A(sum_Q_A),
        .calib_N0(calib_N0), .calib_Velec(calib_Velec), .calib_VarA(calib_VarA), .calib_eta(calib_eta),
        .T_final(T_final), .xi_final(xi_final), .data_ready(data_ready)
    );

    // Reloj a 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Proceso de Test
    initial begin
        // =====================================================================
        // 0. CALIBRACIÓN INICIAL (Como si la CPU escribiera los registros)
        // =====================================================================
        rst = 1'b1; start_calc = 1'b0;
        
        // Asumimos que 1 SNU = 10000 unidades de tu ADC
        calib_N0    = 32'd10000; // Ruido de vacío
        calib_Velec = 32'd1000;  // Ruido de la placa (10% de N0)
        calib_VarA  = 32'd40000; // Alice modula con 4 SNU
        calib_eta   = 32'd39321; // Eficiencia 0.6 en Q16.16 (0.6 * 65536)
        
        // Sumatorios simples a 0 (Asumimos que el hardware analógico está perfecto sin DC Bias)
        sum_P_B = 0; sum_P_A = 0; sum_Q_B = 0; sum_Q_A = 0;
        
        #20 rst = 1'b0;
        $display("\n=======================================================");
        $display("   SISTEMA DE DEFENSA QKD INICIADO - MONITOREO ACTIVO");
        $display("=======================================================\n");

        // =====================================================================
        // ESCENARIO 1: CANAL LIMPIO (Transmisión segura)
        // =====================================================================
        $display("[INFO] Analizando Bloque de Datos 1 (Canal aparentemente seguro)...");
        // Matemáticas emuladas: T = 0.5, VarB = 31000, Cov = 20000
        // (Multiplicamos por N=52224 y dividimos entre 2 para P y Q)
        sum_sq_P_B = 64'd809_472_000; sum_sq_Q_B = 64'd809_472_000; 
        sum_cov_P  = 64'd522_240_000; sum_cov_Q  = 64'd522_240_000;
        
        @(posedge clk) start_calc = 1'b1;
        @(posedge clk) start_calc = 1'b0;
        
        // Esperamos 50 ciclos para que la división IP Radix2 termine
        repeat(50) @(posedge clk); 
        
        $display("  -> Transmitancia estimada (T): %0f", real'(T_final) / 65536.0);
        $display("  -> Ruido en Exceso (xi) crudo: %0d unidades ADC", xi_final);
        
        // En un canal limpio, el ruido en exceso debe estar cerca de 0
        if (xi_final < 5000) 
            $display("  [ SEGURO ] No hay evidencia de espionaje. Destilando clave...\n");
        else 
            $display("  [ ALERTA ] Posible espia detectado.\n");


        // =====================================================================
        // ESCENARIO 2: ATAQUE DE EVE (Intercept-Resend)
        // =====================================================================
        $display("[INFO] Analizando Bloque de Datos 2 (Ataque en curso)...");
        // Matemáticas emuladas: Eve destruye la correlación y mete ruido masivo.
        // T cae (Covarianza baja a 10000) y VarB se dispara a 70000.
        sum_sq_P_B = 64'd1_827_840_000; sum_sq_Q_B = 64'd1_827_840_000; 
        sum_cov_P  = 64'd261_120_000;   sum_cov_Q  = 64'd261_120_000;
        
        @(posedge clk) start_calc = 1'b1;
        @(posedge clk) start_calc = 1'b0;
        
        // Esperamos 50 ciclos a que el hardware calcule
        repeat(50) @(posedge clk); 
        
        $display("  -> Transmitancia estimada (T): %0f", real'(T_final) / 65536.0);
        $display("  -> Ruido en Exceso (xi) crudo: %0d unidades ADC", xi_final);
        
        // Eve ha inyectado muchísimo ruido, xi superará ampliamente nuestro umbral
        if (xi_final > 15000) begin
            $display("  [ PELIGRO ] ¡ATAQUE CUANTICO DETECTADO! ");
            $display("              El Ruido en Exceso viola el limite de Holevo.");
            $display("              Abortando comunicacion. Borrando buffer de memoria...\n");
        end
        
        $display("=======================================================\n");
        $finish;
    end

endmodule