`timescale 1ns / 1ps

module fsm_estimator #(
    parameter NUM_SAMPLES = 26112 // Muestras exactas a sacrificar
)(
    input  logic        clk,
    input  logic        rst,
    
    // Señales de la CPU
    input  logic        start,         // Pulso para arrancar
    input  logic        ping_pong_bit, // 0 = Leer Mitad A, 1 = Leer Mitad B de Bob
    output logic        done,          // Bandera de terminado
    
    // Interfaz con la BRAM de Máscara (Pointer RAM)
    output logic [14:0] ptr_addr,      // Direcciones: 0 a 26111
    input  logic [15:0] ptr_data,      // El índice extraído (ej. 5, 12, 502...)
    
    // Interfaz con las BRAMs Gigantes
    output logic [16:0] bob_addr,      // Dirección hacia Bob {ping_pong, 16 bits}
    output logic [14:0] alice_addr,    // Dirección hacia Alice
    
    // Control hacia los multiplicadores (MACs)
    output logic        mac_clear,
    output logic        mac_enable
);

    // =========================================================================
    // 1. DEFINICIÓN DE ESTADOS
    // =========================================================================
    typedef enum logic [1:0] {
        IDLE,       // Esperando a la CPU
        RUN,        // Recorriendo las memorias
        DRAIN,      // Esperando a que el pipeline se vacíe
        DONE        // Fin del proceso
    } state_t;
    
    state_t state, next_state;

    // =========================================================================
    // 2. REGISTROS Y CONTADORES
    // =========================================================================
    logic [14:0] counter;           // Cuenta de 0 a 26111
    logic [14:0] count_delay_1;     // El contador retrasado 1 ciclo
    logic        active_flag;       // Vale 1 cuando estamos generando direcciones
    logic [3:0]  drain_counter; // Contador para vaciar el pipeline
    
    // Shift registers para el mac_enable (retrasamos la señal 'active_flag' 2 ciclos)
    logic enable_delay_1;
    logic enable_delay_2;

    // =========================================================================
    // 3. LÓGICA SECUENCIAL DE LA FSM
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            counter        <= '0;
            count_delay_1  <= '0;
            enable_delay_1 <= 1'b0;
            enable_delay_2 <= 1'b0;
            drain_counter  <= '0; // NUEVO
        end else begin
            state <= next_state;
            
            enable_delay_1 <= active_flag;
            enable_delay_2 <= enable_delay_1;
            count_delay_1  <= counter;

            if (state == IDLE) begin
                counter       <= '0;
                drain_counter <= '0; // NUEVO
            end else if (state == RUN) begin
                if (counter < NUM_SAMPLES - 1) begin
                    counter <= counter + 1'b1;
                end
            end else if (state == DRAIN) begin
                drain_counter <= drain_counter + 1'b1; // NUEVO: Contamos los ciclos muertos
            end
        end
    end

    // =========================================================================
    // 4. LÓGICA COMBINACIONAL DE ESTADOS Y SALIDAS
    // =========================================================================
    always_comb begin
        // Valores por defecto
        next_state  = state;
        active_flag = 1'b0;
        mac_clear   = 1'b0;
        done        = 1'b0;

        case (state)
            IDLE: begin
                mac_clear = 1'b1; // Mantenemos los acumuladores reseteados
                if (start) begin
                    next_state = RUN;
                end
            end
            
            RUN: begin
                active_flag = 1'b1; // Arrancamos la tubería de direcciones
                if (counter == NUM_SAMPLES - 1) begin
                    next_state = DRAIN;
                end
            end
            
            DRAIN: begin
                // Esperamos a que los últimos datos crucen las memorias (2 ciclos) 
                // y los MACs terminen de multiplicar/sumar (3 ciclos).
                // Obligamos a la FSM a esperar 8 ciclos por seguridad.
                if (drain_counter == 4'd8) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                done = 1'b1; // Levantamos la bandera para la CPU
                // La FSM vuelve sola a IDLE en el siguiente ciclo o se queda
                // aquí hasta que la CPU baje la señal 'start' (opcional).
                if (!start) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // =========================================================================
    // 5. ENRUTAMIENTO DE DIRECCIONES (El Cerebro en acción)
    // =========================================================================
    
    // Ciclo T: Pedimos el índice a la Pointer RAM usando el contador actual
    assign ptr_addr = counter;

    // Ciclo T+1: Pedimos los datos a Bob y a Alice
    // A Bob le pasamos el índice que acaba de salir de la Pointer RAM (ptr_data)
    assign bob_addr = {ping_pong_bit, ptr_data};
    
    // A Alice le pasamos el índice secuencial, pero usando el contador retrasado
    assign alice_addr = count_delay_1;

    // Ciclo T+2: ¡Llegan los datos! Activamos los multiplicadores
    assign mac_enable = enable_delay_2;

endmodule