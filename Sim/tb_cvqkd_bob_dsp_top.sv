`timescale 1ns / 1ps

module tb_cvqkd_bob_dsp_top();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam ADC_WIDTH = 16;
    localparam NUM_SAMPLES = 1601; // 100 tramas * 16 muestras

    logic clk;
    logic rst;
    
    logic signed [ADC_WIDTH-1:0] p_in;
    logic signed [ADC_WIDTH-1:0] q_in;
    logic                        valid_in;
    
    logic signed [ADC_WIDTH-1:0] p_out;
    logic signed [ADC_WIDTH-1:0] q_out;
    logic                        valid_out;

    // Memorias para leer los vectores de MATLAB
    logic [31:0] memoria_in [0:NUM_SAMPLES-1];
    logic [31:0] memoria_expected [0:NUM_SAMPLES-1]; // NUEVO: Para el Golden Model
    
    // Identificador del archivo de salida
    integer file_out;

    // Contadores para la autoverificación
    integer out_counter = 0;   // Cuenta las muestras válidas que salen de Vivado (deberían ser 1500)
    integer expected_idx = 0;  // Recorre el archivo esperado de MATLAB (va hasta 1600)
    integer error_counter = 0; // Cuenta los desajustes

    // Variables internas para la comparación matemática
    logic signed [15:0] exp_q, exp_p;
    integer diff_p, diff_q;

    // =========================================================================
    // 2. Instanciación del Top-Level (DUT)
    // =========================================================================
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(ADC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .p_in(p_in),
        .q_in(q_in),
        .valid_in(valid_in),
        .p_out(p_out),
        .q_out(q_out),
        .valid_out(valid_out)
    );

    // =========================================================================
    // 3. Generación de Reloj (100 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // 4. Proceso de Captura y Verificación Automática (Monitor)
    // =========================================================================
    initial begin
        // ¡CUIDADO! Asegúrate de que las barras son las correctas '/'
        file_out = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_outputs.txt", "w");
        if (file_out == 0) begin
            $display("ERROR: No se pudo crear el archivo de salida.");
            $finish;
        end
    end

    always_ff @(posedge clk) begin
        if (valid_out) begin
            // 4.1. Guardamos el archivo igual que hacíamos antes
            $fdisplay(file_out, "%04x%04x", q_out[15:0], p_out[15:0]);

            // 4.2. Lógica de Autoverificación
            // Si el índice esperado apunta al piloto (múltiplos de 16: 0, 16, 32...), lo saltamos.
            if (expected_idx % 16 == 0) begin
                expected_idx++; 
            end

            // Extraemos los valores esperados de la RAM del testbench
            exp_q = memoria_expected[expected_idx][31:16];
            exp_p = memoria_expected[expected_idx][15:0];

            // Comparamos tolerando +/- 1 bit de diferencia (ruido de cuantización interno del DSP)
            diff_p = $signed(p_out) - exp_p;
            diff_q = $signed(q_out) - exp_q;

            if (diff_p < -1 || diff_p > 1 || diff_q < -1 || diff_q > 1) begin
                if (error_counter < 15) begin // Imprimimos solo los primeros 15 errores para no saturar la consola
                    $display("ERROR HW -> Salida %0d: Esperado Q=%h P=%h | Vivado Q=%h P=%h", 
                              out_counter, exp_q, exp_p, q_out[15:0], p_out[15:0]);
                end
                error_counter++;
            end

            expected_idx++;
            out_counter++;
        end
    end

    // =========================================================================
    // 5. Proceso de Estímulos (Inyección de Datos)
    // =========================================================================
    initial begin
        // Cargar archivos de MATLAB
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/input_vectors.txt", memoria_in);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/expected_outputs.txt", memoria_expected);

        // Estado inicial
        rst = 1'b1;
        valid_in = 1'b0;
        p_in = '0;
        q_in = '0;

        // Reset síncrono
        #20;
        rst = 1'b0;
        $display("--- INICIANDO SIMULACIÓN CON AUTOVERIFICACIÓN ---");

        // Inyectamos los 1600 datos sin pausa
        for (int i = 0; i < NUM_SAMPLES; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            q_in     <= memoria_in[i][31:16];
            p_in     <= memoria_in[i][15:0];
        end

        // Dejamos de inyectar datos
        @(posedge clk);
        valid_in <= 1'b0;
        p_in     <= '0;
        q_in     <= '0;

        // Esperamos a que los CORDIC terminen de procesar
        repeat(100) @(posedge clk);
        
        $fclose(file_out);

        // =========================================================================
        // 6. Veredicto Final por Pantalla (El "Check")
        // =========================================================================
        $display(" ");
        $display("=================================================================");
        $display("                  REPORTE DE AUTOVERIFICACIÓN                    ");
        $display("=================================================================");
        $display("Muestras utiles recibidas por Vivado: %0d / 1500", out_counter);
        
        if (out_counter == 1500 && error_counter == 0) begin
            $display(" ");
            $display("    [ OK ]  ¡CHECK SUPERADO! ");
            $display("            El hardware coincide al 100%% con el Golden Model.");
            $display(" ");
        end else begin
            $display(" ");
            $display("    [ X ]   ¡FALLO DE VERIFICACIÓN! ");
            if (out_counter != 1500)
                $display("            Error critico: Se esperaban 1500 datos y llegaron %0d", out_counter);
            if (error_counter > 0)
                $display("            Muestras con valores incorrectos: %0d", error_counter);
            $display(" ");
        end
        $display("=================================================================");

        $finish;
    end

endmodule