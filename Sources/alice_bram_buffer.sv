`timescale 1ns / 1ps

module alice_bram_buffer #(
    parameter DATA_WIDTH = 32,    // 16 bits Q_A + 16 bits P_A
    parameter ADDR_WIDTH = 15     // 2^15 = 32768 posiciones totales
)(
    // =========================================================
    // PUERTO A: ESCRITURA (Conectado al DMA / Red Ethernet)
    // =========================================================
    input  logic                  clk_wr,     // Reloj del bus del procesador
    input  logic                  we,         // Write Enable (Habilita la escritura)
    input  logic [ADDR_WIDTH-1:0] wr_addr,    // Dirección donde guardar (0 a 26111)
    input  logic [DATA_WIDTH-1:0] wr_data,    // Dato que llega de Alice {Q_A, P_A}

    // =========================================================
    // PUERTO B: LECTURA (Conectado a tu Acelerador Matemático)
    // =========================================================
    input  logic                  clk_rd,     // Reloj del DSP (100 MHz)
    input  logic [ADDR_WIDTH-1:0] rd_addr,    // Dirección que el acelerador quiere leer
    output logic [DATA_WIDTH-1:0] rd_data     // Dato extraído hacia los multiplicadores
);

    // INFERENCIA DE MEMORIA BRAM
    // Obligamos a Vivado a usar RAM física en el silicio
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // LÓGICA DE ESCRITURA
    always_ff @(posedge clk_wr) begin
        if (we) begin
            ram[wr_addr] <= wr_data;
        end
    end

    // LÓGICA DE LECTURA (Latencia de 1 ciclo)
    always_ff @(posedge clk_rd) begin
        rd_data <= ram[rd_addr];
    end

endmodule