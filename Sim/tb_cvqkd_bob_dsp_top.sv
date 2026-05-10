`timescale 1ns / 1ps

module tb_cvqkd_bob_dsp_top();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam ADC_WIDTH = 16;
    localparam NUM_SAMPLES_IN = 55713;  // Toda la secuencia de la fibra
    localparam NUM_SAMPLES_OUT = 52230; // Solo las muestras de datos recuperadas

    logic clk;
    logic rst;
    
    logic signed [ADC_WIDTH-1:0] p_in;
    logic signed [ADC_WIDTH-1:0] q_in;
    logic                        valid_in;
    
    logic signed [ADC_WIDTH-1:0] p_out;
    logic signed [ADC_WIDTH-1:0] q_out;
    logic                        valid_out;

    // Memorias para leer los vectores de MATLAB
    logic [31:0] memoria_in [0:NUM_SAMPLES_IN-1];
    logic [31:0] memoria_expected [0:NUM_SAMPLES_OUT-1]; // NUEVO: Para el Golden Model
    
    // Identificador del archivo de salida
    integer file_out;
    integer file_err; // Archivo para log de errores

    // Contadores para la autoverificación
    integer out_counter = 0;   // Cuenta las muestras válidas que salen de Vivado
    integer expected_idx = 0;  // Recorre el archivo esperado de MATLAB
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
        file_err = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_errors.txt", "w");
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
            // MATLAB truncó la exportación a 52224 datos (N_BOB_DATA). 
            // Si el DSP escupe las 52230, dejamos de comparar las últimas 6 para no leer basura.
            if (expected_idx < 52224) begin
                // Extraemos los valores esperados de la RAM del testbench
                exp_q = memoria_expected[expected_idx][31:16];
                exp_p = memoria_expected[expected_idx][15:0];
    
                // Comparamos tolerando +/- 1 bit de diferencia (ruido de cuantización interno del DSP)
                diff_p = $signed(p_out) - exp_p;
                diff_q = $signed(q_out) - exp_q;
    
                // NUEVO: Escribimos SIEMPRE el error en el archivo para que MATLAB lo grafique.
                // Formato: 3 columnas separadas por espacio -> [Muestra] [Error P] [Error Q]
                if (file_err != 0) begin
                    $fdisplay(file_err, "%0d %0d %0d", out_counter, diff_p, diff_q);
                end

                if (diff_p < -1 || diff_p > 1 || diff_q < -1 || diff_q > 1) begin
                    if (error_counter < 15) begin // Imprimimos solo los primeros 15 errores para no saturar la consola
                        $display("ERROR HW -> Salida %0d: Esperado Q=%h P=%h | Vivado Q=%h P=%h", 
                                  out_counter, exp_q, exp_p, q_out[15:0], p_out[15:0]);
                    end
                    error_counter++;
                end
    
                expected_idx++;
            end
            
            out_counter++;
        end
    end

    // =========================================================================
    // 5. Proceso de Estímulos (Inyección de Datos)
    // =========================================================================
    initial begin
        // Cargar archivos de MATLAB (los copiados a Sim)
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_raw_adc.txt", memoria_in);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_ram.txt", memoria_expected);

        // Estado inicial
        rst = 1'b1;
        valid_in = 1'b0;
        p_in = '0;
        q_in = '0;

        // Reset síncrono
        #20;
        rst = 1'b0;
        $display("--- INICIANDO SIMULACIÓN CON AUTOVERIFICACIÓN ---");

        // Inyectamos todos los datos de la fibra sin pausa
        for (int i = 0; i < NUM_SAMPLES_IN; i++) begin
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
        if (file_err != 0) $fclose(file_err);
        
        
    
        // =========================================================================
        // 6. Veredicto Final por Pantalla (El "Check")
        // =========================================================================
        $display(" ");
        $display("=================================================================");
        $display("                  REPORTE DE AUTOVERIFICACIÓN                    ");
        $display("=================================================================");
        $display("Muestras utiles recibidas por Vivado: %0d / %0d", out_counter, NUM_SAMPLES_OUT);
        
        if (out_counter == NUM_SAMPLES_OUT && error_counter == 0) begin
            $display(" ");
            $display("    [ OK ]  ¡CHECK SUPERADO! ");
            $display("            El hardware coincide al 100%% con el Golden Model.");
            $display(" ");
        end else begin
            $display(" ");
            $display("    [ X ]   ¡FALLO DE VERIFICACIÓN! ");
            if (out_counter != NUM_SAMPLES_OUT)
                $display("            Error critico: Se esperaban %0d datos y llegaron %0d", NUM_SAMPLES_OUT, out_counter);
            if (error_counter > 0)
                $display("            Muestras con valores incorrectos: %0d", error_counter);
            $display(" ");
        end
        $display("=================================================================");

        $finish;
    end

endmodule