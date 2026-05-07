`timescale 1ns / 1ps

module LLR_math_unit #(
    parameter signed [63:0] N_SAMPLES = 64'sd26112,
    // (2^48) / (2 * 26112^2) = 206408.84 -> 206409
    parameter signed [63:0] INV_2N2   = 64'sd206409 
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start_calc, // Pulso de inicio cuando la FSM termina
    
    // Datos desde los MACs
    input  logic signed [63:0] sum_sq_P_B, sum_P_B, sum_cov_P, sum_P_A,
    input  logic signed [63:0] sum_sq_Q_B, sum_Q_B, sum_cov_Q, sum_Q_A,
    
    // Calibración
    input  logic signed [31:0] calib_VarA,
    
    // Salidas para el cálculo de LLR
    output logic signed [31:0] T_final,     // Transmitancia T (Q16.16)
    output logic signed [31:0] T_sqrt,      // Raíz cuadrada de T (Q16.16)
    output logic signed [31:0] sigma_sq,    // Varianza sigma^2 (Q16.16)
    output logic signed [31:0] sigma,       // Desviación estándar sigma (Q16.16)
    output logic               data_ready
);

    // --- Señales de control del pipeline ---
    logic pipe_v1, pipe_v2, pipe_v3;

    // ===========================================================
    // ETAPA 1: Productos cruzados ((Sum)^2 y SumA*SumB)
    // ===========================================================
    // Estos cálculos son IMPRESCINDIBLES para la fórmula:
    // Var = (N*SumSq - (Sum)^2) / N^2
    logic signed [63:0] cross_P_AB, cross_Q_AB;
    logic signed [63:0] sq_sum_P_B, sq_sum_Q_B; 

    always_ff @(posedge clk) begin
        if (rst) begin
            {cross_P_AB, cross_Q_AB, sq_sum_P_B, sq_sum_Q_B} <= '0;
            pipe_v1 <= 1'b0;
        end else begin
            pipe_v1 <= start_calc;
            if (start_calc) begin
                cross_P_AB <= sum_P_A * sum_P_B;
                cross_Q_AB <= sum_Q_A * sum_Q_B;
                sq_sum_P_B <= sum_P_B * sum_P_B; // Necesario para la varianza
                sq_sum_Q_B <= sum_Q_B * sum_Q_B; // Necesario para la varianza
            end
        end
    end

    // ===========================================================
    // ETAPA 2: Numeradores (Precisión de 64 bits)
    // ===========================================================
    logic signed [63:0] num_cov_AB, num_var_B;

    always_ff @(posedge clk) begin
        if (rst) begin
            {num_cov_AB, num_var_B} <= '0;
            pipe_v2 <= 1'b0;
        end else begin
            pipe_v2 <= pipe_v1;
            num_cov_AB <= (N_SAMPLES * (sum_cov_P  + sum_cov_Q))  - (cross_P_AB + cross_Q_AB);
            num_var_B  <= (N_SAMPLES * (sum_sq_P_B + sum_sq_Q_B)) - (sq_sum_P_B + sq_sum_Q_B);
        end
    end

    // ===========================================================
    // ETAPA 3: Normalización y Escala Q16.16
    // Multiplicamos por el inverso de 2N^2 usando 128 bits para evitar overflow
    // ===========================================================
    logic signed [31:0] cov_AB_pure;
    logic signed [31:0] var_B_pure;

    always_ff @(posedge clk) begin
        if (rst) begin
            {cov_AB_pure, var_B_pure} <= '0;
            pipe_v3 <= 1'b0;
        end else begin
            pipe_v3 <= pipe_v2;
            cov_AB_pure <= ($signed(128'(num_cov_AB)) * INV_2N2) >>> 48;
            var_B_pure  <= ($signed(128'(num_var_B))  * INV_2N2) >>> 48;
        end
    end

    // Asignación de sigma_sq
    assign sigma_sq = var_B_pure;

    // ===========================================================
    // ETAPA 4: IPs de División y Raíz Cuadrada
    // ===========================================================
    
    // 1. División para obtener T
    logic [47:0] div_t_raw;
    logic        div_done;

    div_gen_48_32_params div_inst (
        .aclk(clk),
        .s_axis_divisor_tdata(calib_VarA),    
        .s_axis_divisor_tvalid(pipe_v3),
        .s_axis_dividend_tdata(cov_AB_pure),  
        .s_axis_dividend_tvalid(pipe_v3),
        .m_axis_dout_tdata(div_t_raw),
        .m_axis_dout_tvalid(div_done)
    );
    assign T_final = div_t_raw[31:0] << 1;

    // 2. Raíz Cuadrada para Sigma = sqrt(sigma_sq)
    // Debes instanciar el IP "CORDIC 6.0" en modo "Square Root"
    logic [31:0] sqrt_sigma_raw;
    cordic_sqrt_q16_16 sqrt_sigma_inst (
        .aclk(clk),
        .s_axis_cartesian_tdata(sigma_sq),
        .s_axis_cartesian_tvalid(pipe_v3),
        .m_axis_dout_tdata(sqrt_sigma_raw),
        .m_axis_dout_tvalid() // Podríamos usar este valid también
    );
    assign sigma = sqrt_sigma_raw << 16;

    // 3. Raíz Cuadrada para T_sqrt = sqrt(T)
    // Esperamos a que salga T del divisor para calcular su raíz
    logic [31:0] sqrt_t_raw;
    cordic_sqrt_q16_16 sqrt_t_inst (
        .aclk(clk),
        .s_axis_cartesian_tdata(T_final),
        .s_axis_cartesian_tvalid(div_done),
        .m_axis_dout_tdata(sqrt_t_raw),
        .m_axis_dout_tvalid(data_ready) // Esta será nuestra señal final de "Listos"
    );
    assign T_sqrt = sqrt_t_raw << 8;

endmodule