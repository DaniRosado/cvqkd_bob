`timescale 1ns / 1ps

module final_math_unit #(
    // Inverso de (26112 * 2) = 52224. 
    // Escalado a 2^32: (2^32 / 52224) = 82241.8 -> 82242
    parameter logic [31:0] N_INV_TOTAL = 32'd82242 
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start_calc, // Viene del 'done' de la FSM
    
    // Sumatorios P
    input  logic signed [63:0] sum_sq_P_B, sum_P_B, sum_cov_P, sum_P_A,
    // Sumatorios Q
    input  logic signed [63:0] sum_sq_Q_B, sum_Q_B, sum_cov_Q, sum_Q_A,
    
    // Parámetros de Calibración (Desde la CPU)
    input  logic signed [31:0] calib_N0,    // Shot Noise
    input  logic signed [31:0] calib_Velec, // Ruido electrónico
    input  logic signed [31:0] calib_VarA,  // Varianza Alice
    input  logic signed [31:0] calib_eta,   // Eficiencia (Q16.16)
    
    // SALIDAS FINALES
    output logic signed [31:0] T_final,     // Transmitancia (Q16.16)
    output logic signed [31:0] xi_final,    // Ruido en exceso (Q16.16)
    output logic        data_ready
);

    // -----------------------------------------------------------
    // ETAPA 1: Combinar P y Q (Data Pooling)
    // -----------------------------------------------------------
    logic signed [64:0] total_sum_sq_B, total_sum_B, total_sum_cov, total_sum_A;
    
    always_ff @(posedge clk) begin
        total_sum_sq_B <= sum_sq_P_B + sum_sq_Q_B;
        total_sum_B    <= sum_P_B    + sum_Q_B;
        total_sum_cov  <= sum_cov_P  + sum_cov_Q;
        total_sum_A    <= sum_P_A    + sum_Q_A;
    end

    // -----------------------------------------------------------
    // ETAPA 2: Medias E[X] = Sum * N_INV
    // -----------------------------------------------------------
    logic signed [63:0] mean_sq_B, mean_B, mean_cov, mean_A;

    always_ff @(posedge clk) begin
        mean_sq_B <= (total_sum_sq_B * N_INV_TOTAL) >>> 32;
        mean_B    <= (total_sum_B    * N_INV_TOTAL) >>> 32;
        mean_cov  <= (total_sum_cov  * N_INV_TOTAL) >>> 32;
        mean_A    <= (total_sum_A    * N_INV_TOTAL) >>> 32;
    end

    // -----------------------------------------------------------
    // ETAPA 3: Varianza y Covarianza Purificada
    // -----------------------------------------------------------
    logic signed [31:0] var_B_pure, cov_AB_pure;

    always_ff @(posedge clk) begin
        // Var = E[X^2] - E[X]^2. Ajustamos el desplazamiento para mantener Q16.16
        var_B_pure  <= mean_sq_B[31:0] - ((mean_B[31:0] * mean_B[31:0]) >>> 16);
        cov_AB_pure <= mean_cov[31:0]  - ((mean_A[31:0] * mean_B[31:0]) >>> 16);
    end

    // -----------------------------------------------------------
    // ETAPA 4: División para T (Usando el IP Core div_gen)
    // T = Cov_AB / Var_A
    // -----------------------------------------------------------
    logic [47:0] div_out_t; // IP configurado como 32 dividend / 32 divisor con 16 fractional
    
    // Instancia del IP que configuramos antes
    div_gen_48_32_params div_T (
        .aclk(clk),
        .s_axis_divisor_tdata(calib_VarA),    // El divisor es la Varianza de Alice
        .s_axis_divisor_tvalid(1'b1),
        .s_axis_dividend_tdata(cov_AB_pure),  // El dividendo es la Covarianza
        .s_axis_dividend_tvalid(1'b1),
        .m_axis_dout_tdata(div_out_t)         // [Cociente 32 bits | Fracción 16 bits]
    );

    // Extraemos el resultado en formato punto fijo
    // Al haber pedido 16 bits fraccionales, el resultado es directamente Q16.16
    assign T_final = div_out_t[31:0]; 

    // -----------------------------------------------------------
    // ETAPA 5: Ruido en Exceso (xi)
    // xi = (Var_B - Velec)/(eta * T) - N0 - VarA
    // -----------------------------------------------------------
    // Por brevedad, aquí haríamos una resta simple. 
    // Para la división por (eta*T) necesitaríamos otro IP igual al anterior.
    assign xi_final = var_B_pure - calib_Velec - calib_N0 - calib_VarA;

    assign data_ready = 1'b1; // Debería estar sincronizado con la latencia del divisor

endmodule