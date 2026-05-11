def simulate_interpolator(num_pilots, valid_interval=16):
    state = "ESPERAR_A"
    contador_datos = 0
    fifo_re_count = 0
    valid_in = False
    
    # Simulate for enough cycles
    total_cycles = num_pilots * valid_interval + 100
    
    for cycle in range(total_cycles):
        # Determine valid_in
        valid_in = (cycle % valid_interval == 0) and (cycle < num_pilots * valid_interval)
        
        fifo_re = False
        
        if state == "ESPERAR_A":
            if valid_in:
                state = "ESPERAR_B"
        elif state == "ESPERAR_B":
            if valid_in:
                contador_datos = 15
                state = "INTERPOLAR"
        elif state == "INTERPOLAR":
            if contador_datos > 0:
                fifo_re = True
                contador_datos -= 1
            else:
                if valid_in:
                    contador_datos = 15
                    state = "INTERPOLAR"
                else:
                    state = "ESPERAR_B"
                    
        if fifo_re:
            fifo_re_count += 1
            
    return fifo_re_count

print(f"Total data read: {simulate_interpolator(3483, 16)}")
