`timescale 1ns / 1ps

module gain_compensation #(
    parameter IN_WIDTH  = 18, // Q3.15
    parameter OUT_WIDTH = 16  // Q1.15
)(
    input  logic clk,
    input  logic rst,
    input  logic signed [IN_WIDTH-1:0]  p_in,
    input  logic signed [IN_WIDTH-1:0]  q_in,
    input  logic                        valid_in,

    output logic signed [OUT_WIDTH-1:0] p_out,
    output logic signed [OUT_WIDTH-1:0] q_out,
    output logic                        valid_out
);

    // Constante: 1/1.64676 = 0.60725...
    // En Q0.15: 0.60725 * 2^15 = 19898
    localparam signed [15:0] GAIN_INV = 16'sd19898;

    // Registros internos para la multiplicación
    // 18 bits * 16 bits = 34 bits
    logic signed [33:0] p_mult;
    logic signed [33:0] q_mult;

    always_ff @(posedge clk) begin
        if (rst) begin
            p_out     <= '0;
            q_out     <= '0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            
            if (valid_in) begin
                // Multiplicación
                p_mult = p_in * GAIN_INV;
                q_mult = q_in * GAIN_INV;

                // Truncado/Selección de bits:
                // El resultado tiene 15+15 = 30 bits fraccionarios.
                // Queremos volver a 15 bits fraccionarios.
                // p_mult[30:15] extrae la parte Q1.15 correcta.
                p_out <= p_mult[30:15];
                q_out <= q_mult[30:15];
            end
        end
    end

endmodule