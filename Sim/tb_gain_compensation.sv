`timescale 1ns / 1ps

module tb_gain_compensation_burst();

    logic clk;
    logic rst;
    logic signed [17:0] p_in, q_in;
    logic valid_in;
    logic signed [15:0] p_out, q_out;
    logic valid_out;

    // Instancia del módulo
    gain_compensation dut (.*);

    // Generador de reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Inicialización
        rst = 1; p_in = 0; q_in = 0; valid_in = 0;
        #20 rst = 0;
        @(posedge clk);

        $display("--- INICIANDO RÁFAGA DE 5 VALORES ---");

        // Simulamos la ráfaga del CORDIC (5 ciclos seguidos)
        for (int i = 0; i < 5; i++) begin
            valid_in <= 1'b1;
            // Metemos valores crecientes "inflados" (simulando ganancia 1.64)
            p_in <= 18'sd40000 + (i * 2000); 
            q_in <= 18'sd10000 + (i * 1000);
            @(posedge clk);
        end

        // Fin de la ráfaga
        valid_in <= 1'b0;
        p_in <= 0;
        q_in <= 0;

        #50;
        $display("--- TEST FINALIZADO ---");
        $finish;
    end

endmodule