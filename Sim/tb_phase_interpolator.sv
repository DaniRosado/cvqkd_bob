`timescale 1ns / 1ps

module tb_phase_interpolator();

    // =========================================================================
    // 1. Declaración de Señales
    // =========================================================================
    localparam THETA_WIDTH = 18; // Formato Q3.15

    logic clk;
    logic rst;
    logic signed [THETA_WIDTH-1:0] theta_in;
    logic valid_in;

    logic signed [THETA_WIDTH-1:0] theta_out;
    logic valid_out;

    // =========================================================================
    // 2. Instanciación del DUT
    // =========================================================================
    phase_interpolator #(
        .THETA_WIDTH(THETA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .theta_in(theta_in),
        .valid_in(valid_in),
        .theta_out(theta_out),
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
    // 4. Estímulos (Inyección de Pilotos)
    // =========================================================================
    initial begin
        // A) Reset del sistema
        rst = 1'b1;
        valid_in = 1'b0;
        theta_in = '0;
        #20;
        rst = 1'b0;
        #10;

        $display("--- INICIANDO TEST DEL INTERPOLADOR ---");

        // B) Llega el Piloto A (Inicio de Trama 1)
        // Simulamos que el CORDIC midió un ángulo de 0
        @(posedge clk);
        valid_in <= 1'b1;
        theta_in <= 18'sd0; 
        @(posedge clk);
        valid_in <= 1'b0;

        // Esperamos 15 ciclos simulando que están entrando los datos a la FIFO
        repeat(15) @(posedge clk);

        // C) Llega el Piloto B (Inicio de Trama 2)
        // Simulamos que la fase ha subido a +32768 (1 radian en Q1.15)
        @(posedge clk);
        valid_in <= 1'b1;
        theta_in <= 18'sd32768; 
        @(posedge clk);
        valid_in <= 1'b0;

        // Ahora el bloque pasará al estado INTERPOLAR y estará escupiendo 
        // 15 ángulos durante 15 ciclos. Lo dejamos trabajar.
        repeat(16) @(posedge clk);

        // D) Llega el Piloto C (Inicio de Trama 3)
        // Simulamos que la fase cae en picado a -16384 (-0.5 radianes)
        // Esto probará que la rampa matemática funciona también hacia abajo (negativos)
        @(posedge clk);
        valid_in <= 1'b1;
        theta_in <= -18'sd16384; 
        @(posedge clk);
        valid_in <= 1'b0;

        // Dejamos que interpole y termine
        repeat(20) @(posedge clk);

        $display("--- SIMULACION FINALIZADA ---");
        $finish;
    end

endmodule