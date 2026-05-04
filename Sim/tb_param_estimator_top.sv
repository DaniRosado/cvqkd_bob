`timescale 1ns / 1ps

module tb_param_estimator_top();

    // =========================================================================
    // 1. PARÁMETROS Y SEÑALES
    // =========================================================================
    localparam TEST_SAMPLES = 100;
    
    logic clk;
    logic rst;
    logic start;
    logic ping_pong_bit;
    logic done;
    
    // Cables hacia las memorias
    logic [14:0] ptr_addr;
    logic [15:0] ptr_data;
    
    logic [16:0] bob_addr;
    logic [31:0] bob_data;
    
    logic [14:0] alice_addr;
    logic [31:0] alice_data;
    
    // Resultados
    logic signed [63:0] var_P_sum_sq, var_P_sum_val, cov_P_sum_cov, cov_P_sum_alice;
    logic signed [63:0] var_Q_sum_sq, var_Q_sum_val, cov_Q_sum_cov, cov_Q_sum_alice;

    // =========================================================================
    // 2. ARRAYS DE MEMORIA (EMULACIÓN DE BRAMs)
    // =========================================================================
    logic [15:0] mem_ptr   [0:TEST_SAMPLES-1];
    logic [31:0] mem_bob   [0:199]; // 200 posiciones
    logic [31:0] mem_alice [0:TEST_SAMPLES-1];
    logic [63:0] mem_expected [0:7];

    // =========================================================================
    // 3. INSTANCIACIÓN DEL DUT (Reemplazamos 26112 por 100)
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(TEST_SAMPLES)
    ) dut (
        .clk(clk), .rst(rst),
        .start(start), .ping_pong_bit(ping_pong_bit), .done(done),
        .ptr_addr(ptr_addr), .ptr_data(ptr_data),
        .bob_addr(bob_addr), .bob_data(bob_data),
        .alice_addr(alice_addr), .alice_data(alice_data),
        
        .var_P_sum_sq(var_P_sum_sq), .var_P_sum_val(var_P_sum_val),
        .cov_P_sum_cov(cov_P_sum_cov), .cov_P_sum_alice(cov_P_sum_alice),
        
        .var_Q_sum_sq(var_Q_sum_sq), .var_Q_sum_val(var_Q_sum_val),
        .cov_Q_sum_cov(cov_Q_sum_cov), .cov_Q_sum_alice(cov_Q_sum_alice)
    );

    // =========================================================================
    // 4. GENERACIÓN DE RELOJ Y EMULACIÓN DE LATENCIA BRAM (1 CICLO)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ¡ESTO ES VITAL! Simulamos el retraso físico de lectura de una BRAM real
    always_ff @(posedge clk) begin
        ptr_data   <= mem_ptr[ptr_addr];
        bob_data   <= mem_bob[bob_addr[15:0]]; // Ignoramos el bit de ping_pong para el test
        alice_data <= mem_alice[alice_addr];
    end

    // =========================================================================
    // 5. PROCESO PRINCIPAL DE TEST
    // =========================================================================
    
    integer errores = 0;
    
    initial begin
        // A) CARGAR ARCHIVOS (¡Ojo con la ruta!)
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/ptr_ram.txt", mem_ptr);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/bob_ram.txt", mem_bob);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/alice_ram.txt", mem_alice);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/expected_results.txt", mem_expected);

        // B) ESTADO INICIAL
        rst           = 1'b1;
        start         = 1'b0;
        ping_pong_bit = 1'b0;
        
        #20;
        rst = 1'b0;
        
        $display("---------------------------------------------------");
        $display("[INFO] Iniciando Simulacion del Acelerador Hardware...");
        $display("[INFO] Muestras configuradas: %0d", TEST_SAMPLES);

        // C) DISPARO DE LA FSM
        @(posedge clk);
        start = 1'b1; // ¡Damos la orden!
        
        // D) ESPERAR A QUE TERMINE
        wait(done == 1'b1);
        start = 1'b0; // Bajamos la orden
        
        $display("[INFO] FSM ha levantado la bandera 'DONE'.");
        $display("[INFO] Validando los 8 acumuladores...");

        // E) COMPROBACIÓN CONTRA EL GOLDEN MODEL
        // Creamos una variable de error para saber si hubo algun fallo
        
        
        // P
        if (var_P_sum_sq    !== mem_expected[0]) errores++;
        if (var_P_sum_val   !== mem_expected[1]) errores++;
        if (cov_P_sum_cov   !== mem_expected[2]) errores++;
        if (cov_P_sum_alice !== mem_expected[3]) errores++;
        
        // Q
        if (var_Q_sum_sq    !== mem_expected[4]) errores++;
        if (var_Q_sum_val   !== mem_expected[5]) errores++;
        if (cov_Q_sum_cov   !== mem_expected[6]) errores++;
        if (cov_Q_sum_alice !== mem_expected[7]) errores++;

        $display(" ");
        if (errores == 0) begin
            $display("=================================================");
            $display("    [ OK ]  ¡SISTEMA MATEMATICO PERFECTO! ");
            $display("            La FSM y el Pipeline DSP coinciden");
            $display("            al 100%% con el Golden Model.");
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display("    [ X ]   ¡ERROR DE SINCRONIZACION! ");
            $display("            Algunos acumuladores no coinciden.");
            $display("=================================================");
            // Imprimimos uno para ver el error
            $display("Esperado P_Sq: %h", mem_expected[0]);
            $display("Obtenido P_Sq: %h", var_P_sum_sq);
        end
        
        $display("---------------------------------------------------");
        $finish;
    end

endmodule