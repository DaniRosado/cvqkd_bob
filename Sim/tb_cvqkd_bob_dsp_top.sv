`timescale 1ns / 1ps

module tb_cvqkd_bob_dsp_top();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam ADC_WIDTH = 16;
    localparam NUM_SAMPLES = 1600; // 100 tramas * 16 muestras

    logic clk;
    logic rst;
    
    logic signed [ADC_WIDTH-1:0] p_in;
    logic signed [ADC_WIDTH-1:0] q_in;
    logic                        valid_in;
    
    logic signed [ADC_WIDTH-1:0] p_out;
    logic signed [ADC_WIDTH-1:0] q_out;
    logic                        valid_out;

    // Memoria para leer los vectores de MATLAB
    logic [31:0] memoria_in [0:NUM_SAMPLES-1];
    
    // Identificador del archivo de salida
    integer file_out;

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
    // 4. Proceso de Captura (Monitor de Salida)
    // =========================================================================
    // Este bloque vigila en paralelo. Siempre que la FPGA escupa un dato válido, lo guarda.
    initial begin
        // ¡RECUERDA USAR BARRAS NORMALES '/' PARA LA RUTA!
        // Cambia esta ruta a tu carpeta real
        file_out = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_outputs.txt", "w");
        
        if (file_out == 0) begin
            $display("ERROR: No se pudo crear el archivo de salida.");
            $finish;
        end
    end

    always_ff @(posedge clk) begin
        if (valid_out) begin
            // Guardamos en formato Hexadecimal (Q_OUT | P_OUT) igual que hicimos en MATLAB
            $fdisplay(file_out, "%04x%04x", q_out[15:0], p_out[15:0]);
        end
    end

    // =========================================================================
    // 5. Proceso de Estímulos (Inyección de Datos)
    // =========================================================================
    initial begin
        // Cargar archivo de MATLAB (¡Cambia la ruta!)
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/input_vectors.txt", memoria_in);

        // Estado inicial
        rst = 1'b1;
        valid_in = 1'b0;
        p_in = '0;
        q_in = '0;

        // Reset síncrono de 2 ciclos
        #20;
        rst = 1'b0;
        

        $display("--- INICIANDO SIMULACIÓN DEL SISTEMA COMPLETO ---");

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

        // ¡SÚPER IMPORTANTE!
        // Como nuestro hardware tiene "pipeline" (latencia), los últimos datos 
        // todavía están viajando por dentro de los CORDIC y la FIFO.
        // Hay que esperar unos 100 ciclos de reloj para que el hardware termine de escupirlos todos.
        repeat(100) @(posedge clk);

        // Cerramos el archivo y terminamos
        $fclose(file_out);
        $display("--- SIMULACIÓN FINALIZADA. ARCHIVO GUARDADO ---");
        $finish;
    end

endmodule