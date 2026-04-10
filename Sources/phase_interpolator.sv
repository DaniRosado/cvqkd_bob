`timescale 1ns / 1ps

module phase_interpolator #(
    parameter THETA_WIDTH = 18
)(
    input  logic clk,
    input  logic rst,
    input  logic signed [THETA_WIDTH-1:0] theta_in,
    input  logic                          valid_in,

    // Salida hacia la FIFO (inmediata)
    output logic                          fifo_re,
    
    // Salidas hacia el CORDIC 2 (retrasadas 1 ciclo y negadas)
    output logic signed [THETA_WIDTH-1:0] cordic_theta,
    output logic                          cordic_valid
);

    // Registros de la máquina de estados
    logic signed [THETA_WIDTH-1:0] theta_A;
    logic signed [THETA_WIDTH-1:0] delta_theta;
    logic signed [THETA_WIDTH-1:0] acumulador;
    logic [3:0] contador_datos;
    
    // Señal interna para el ángulo raw (sin negar ni retrasar)
    logic signed [THETA_WIDTH-1:0] theta_raw;

    typedef enum logic [1:0] {ESPERAR_A, ESPERAR_B, INTERPOLAR} state_t;
    state_t estado_actual;

    // =========================================================================
    // 1. Lógica Principal (Cálculo de Fase)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            theta_A       <= '0;
            delta_theta   <= '0;
            acumulador    <= '0;
            contador_datos<= '0;
            fifo_re       <= 1'b0;
            theta_raw     <= '0;
            estado_actual <= ESPERAR_A;
        end else begin
            
            fifo_re <= 1'b0; // Por defecto, no pedimos datos a la FIFO

            case (estado_actual)
                ESPERAR_A: begin
                    if (valid_in) begin
                        theta_A <= theta_in;
                        estado_actual <= ESPERAR_B;
                    end
                end
                
                ESPERAR_B: begin
                    if (valid_in) begin
                        delta_theta <= (theta_in - theta_A) >>> 4;
                        acumulador <= theta_A;
                        contador_datos <= 4'd15;
                        theta_A <= theta_in; 
                        estado_actual <= INTERPOLAR;
                    end
                end
                
                INTERPOLAR: begin
                    if (contador_datos > 0) begin
                        acumulador <= acumulador + delta_theta;
                        theta_raw  <= acumulador + delta_theta; 
                        fifo_re    <= 1'b1; // ¡Pedimos el dato a la FIFO!
                        
                        contador_datos <= contador_datos - 1'b1;
                    end else begin
                        // Parche Seamless: Pescar el piloto al vuelo
                        if (valid_in) begin
                            delta_theta <= (theta_in - theta_A) >>> 4;
                            acumulador <= theta_A;
                            contador_datos <= 4'd15;
                            theta_A <= theta_in; 
                            estado_actual <= INTERPOLAR; 
                        end else begin
                            estado_actual <= ESPERAR_B; 
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 2. Registro de Pipeline (Sincronización con FIFO y cambio de signo)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            cordic_valid <= 1'b0;
            cordic_theta <= '0;
        end else begin
            cordic_valid <= fifo_re;
            // ¡EL TRUCO! Negamos el ángulo para deshacer la rotación
            cordic_theta <= -theta_raw; 
        end
    end

endmodule