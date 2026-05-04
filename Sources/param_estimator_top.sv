`timescale 1ns / 1ps

module param_estimator_top #(
    parameter NUM_SAMPLES = 26112
)(
    input  logic        clk,
    input  logic        rst,
    
    // =========================================================================
    // CONTROL DESDE/HACIA LA CPU
    // =========================================================================
    input  logic        start,
    input  logic        ping_pong_bit, // 0 = Mitad A, 1 = Mitad B
    output logic        done,
    
    // =========================================================================
    // INTERFAZ CON LA BRAM DE DIRECCIONES (Pointer RAM)
    // =========================================================================
    output logic [14:0] ptr_addr,
    input  logic [15:0] ptr_data,
    
    // =========================================================================
    // INTERFAZ CON LA BRAM DE BOB (Datos limpios del canal cuántico)
    // =========================================================================
    output logic [16:0] bob_addr,
    input  logic [31:0] bob_data,      // {Q_B [31:16], P_B [15:0]}
    
    // =========================================================================
    // INTERFAZ CON LA BRAM DE ALICE (Datos recibidos por red clásica)
    // =========================================================================
    output logic [14:0] alice_addr,
    input  logic [31:0] alice_data,    // {Q_A [31:16], P_A [15:0]}
    
    // =========================================================================
    // RESULTADOS MATEMÁTICOS (Hacia los registros AXI de la CPU)
    // =========================================================================
    // Cuadraturas P
    output logic signed [63:0] var_P_sum_sq,
    output logic signed [63:0] var_P_sum_val,
    output logic signed [63:0] cov_P_sum_cov,
    output logic signed [63:0] cov_P_sum_alice,
    
    // Cuadraturas Q
    output logic signed [63:0] var_Q_sum_sq,
    output logic signed [63:0] var_Q_sum_val,
    output logic signed [63:0] cov_Q_sum_cov,
    output logic signed [63:0] cov_Q_sum_alice
);

    // =========================================================================
    // 1. DESEMPAQUETADO DE DATOS
    // =========================================================================
    logic signed [15:0] bob_q, bob_p;
    logic signed [15:0] alice_q, alice_p;

    assign bob_q   = bob_data[31:16];
    assign bob_p   = bob_data[15:0];
    assign alice_q = alice_data[31:16];
    assign alice_p = alice_data[15:0];

    // =========================================================================
    // 2. CABLES DE CONTROL INTERNO
    // =========================================================================
    logic mac_clear;
    logic mac_enable;

    // (Nota: Los módulos de covarianza también escupen la suma simple de Bob, 
    // pero como el módulo de varianza ya nos la da en 'var_P_sum_val', 
    // dejamos estos cables al aire para ahorrar pines. Vivado los optimizará).
    logic signed [63:0] ignore_cov_bob_p;
    logic signed [63:0] ignore_cov_bob_q;

    // =========================================================================
    // 3. INSTANCIACIÓN DE LA MÁQUINA DE ESTADOS (El Cerebro)
    // =========================================================================
    fsm_estimator #(
        .NUM_SAMPLES(NUM_SAMPLES)
    ) fsm_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .ping_pong_bit(ping_pong_bit),
        .done(done),
        .ptr_addr(ptr_addr),
        .ptr_data(ptr_data),
        .bob_addr(bob_addr),
        .alice_addr(alice_addr),
        .mac_clear(mac_clear),
        .mac_enable(mac_enable)
    );

    // =========================================================================
    // 4. INSTANCIACIÓN DE LOS ACELERADORES MATEMÁTICOS PARA 'P'
    // =========================================================================
    mac_variance var_P_inst (
        .clk(clk),
        .rst(rst),
        .clear(mac_clear),
        .enable(mac_enable),
        .data_in(bob_p),
        .sum_sq(var_P_sum_sq),
        .sum_val(var_P_sum_val)
    );

    mac_covariance cov_P_inst (
        .clk(clk),
        .rst(rst),
        .clear(mac_clear),
        .enable(mac_enable),
        .data_bob(bob_p),
        .data_alice(alice_p),
        .sum_cov(cov_P_sum_cov),
        .sum_val_bob(ignore_cov_bob_p),
        .sum_val_alice(cov_P_sum_alice)
    );

    // =========================================================================
    // 5. INSTANCIACIÓN DE LOS ACELERADORES MATEMÁTICOS PARA 'Q'
    // =========================================================================
    mac_variance var_Q_inst (
        .clk(clk),
        .rst(rst),
        .clear(mac_clear),
        .enable(mac_enable),
        .data_in(bob_q),
        .sum_sq(var_Q_sum_sq),
        .sum_val(var_Q_sum_val)
    );

    mac_covariance cov_Q_inst (
        .clk(clk),
        .rst(rst),
        .clear(mac_clear),
        .enable(mac_enable),
        .data_bob(bob_q),
        .data_alice(alice_q),
        .sum_cov(cov_Q_sum_cov),
        .sum_val_bob(ignore_cov_bob_q),
        .sum_val_alice(cov_Q_sum_alice)
    );

endmodule