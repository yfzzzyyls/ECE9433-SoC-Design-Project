module lfsr_tb_edge;
    logic clk;
    logic reset;
    logic load;
    logic enable;
    logic [6:0] seed;
    logic [6:0] lfsr_out;
    
    integer error_count = 0;
    integer i, j;
    logic [6:0] prev_value;
    logic [6:0] single_bit_seeds [7];
    logic [6:0] first_repeat_value;
    logic [6:0] seen_values [0:126];
    integer repeat_count;
    
    // Instantiate DUT
    lfsr dut (
        .clk(clk),
        .reset(reset),
        .load(load),
        .enable(enable),
        .seed(seed),
        .lfsr_out(lfsr_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test procedure
    initial begin
        // Initialize signals
        reset = 0;
        load = 0;
        enable = 0;
        seed = 7'b0;
        
        // Wait for clock edge
        @(posedge clk);
        
        // Test 1: Rapid control signal changes
        // Reset and immediately load
        reset = 1;
        @(posedge clk);
        reset = 0;
        seed = 7'b0101010;
        load = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b0101010) begin
            $display("ERROR: Quick reset to load transition failed. Got %b", lfsr_out);
            error_count++;
        end
        load = 0;
        
        // Load and immediately enable
        seed = 7'b1111000;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // Feedback = bit6 XOR bit5 = 1 XOR 1 = 0
        // Expected: 1110000
        if (lfsr_out !== 7'b1110000) begin
            $display("ERROR: Quick load to enable transition failed. Expected 1110000, got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 2: All single-bit patterns
        single_bit_seeds[0] = 7'b0000001;
        single_bit_seeds[1] = 7'b0000010;
        single_bit_seeds[2] = 7'b0000100;
        single_bit_seeds[3] = 7'b0001000;
        single_bit_seeds[4] = 7'b0010000;
        single_bit_seeds[5] = 7'b0100000;
        single_bit_seeds[6] = 7'b1000000;
        
        for (i = 0; i < 7; i++) begin
            seed = single_bit_seeds[i];
            load = 1;
            @(posedge clk);
            if (lfsr_out !== single_bit_seeds[i]) begin
                $display("ERROR: Failed to load single-bit pattern %b", single_bit_seeds[i]);
                error_count++;
            end
            load = 0;
            
            // Do a few shifts to verify it's working
            enable = 1;
            prev_value = lfsr_out;
            for (j = 0; j < 3; j++) begin
                @(posedge clk);
                // Just verify it changes (except for zero case handled separately)
                if (lfsr_out == prev_value && prev_value !== 7'b0) begin
                    $display("ERROR: LFSR stuck with seed %b", single_bit_seeds[i]);
                    error_count++;
                    break;
                end
                prev_value = lfsr_out;
            end
            enable = 0;
        end
        
        // Test 3: Alternating control signals
        seed = 7'b1010101;
        for (i = 0; i < 5; i++) begin
            // Alternate between load and enable
            load = 1;
            @(posedge clk);
            load = 0;
            enable = 1;
            @(posedge clk);
            enable = 0;
        end
        
        // Test 4: Boundary values
        // All ones (already tested in sequence)
        seed = 7'b1111111;
        load = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b1111111) begin
            $display("ERROR: Failed to load all-ones pattern");
            error_count++;
        end
        load = 0;
        
        // Pattern with alternating bits
        seed = 7'b0101010;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // Feedback = bit6 XOR bit5 = 0 XOR 1 = 1
        // Expected: 1010101
        if (lfsr_out !== 7'b1010101) begin
            $display("ERROR: Alternating pattern shift failed. Expected 1010101, got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 5: Control signal combinations (exhaustive)
        // No signals
        prev_value = lfsr_out;
        reset = 0; load = 0; enable = 0;
        @(posedge clk);
        @(posedge clk);
        if (lfsr_out !== prev_value) begin
            $display("ERROR: Value changed with no control signals");
            error_count++;
        end
        
        // Only enable (already tested above)
        
        // Only load
        seed = 7'b0011001;
        reset = 0; load = 1; enable = 0;
        @(posedge clk);
        if (lfsr_out !== 7'b0011001) begin
            $display("ERROR: Load-only failed");
            error_count++;
        end
        
        // Only reset
        reset = 1; load = 0; enable = 0;
        @(posedge clk);
        if (lfsr_out !== 7'b1111111) begin
            $display("ERROR: Reset-only failed");
            error_count++;
        end
        reset = 0;
        
        // Test 6: Very long sequence to catch any overflow/underflow
        seed = 7'b1001001;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        
        // Run for 300 cycles (more than 2 complete sequences)
        first_repeat_value = lfsr_out;
        repeat_count = 0;
        
        for (i = 1; i <= 300; i++) begin
            @(posedge clk);
            if (lfsr_out == first_repeat_value) begin
                repeat_count++;
                // Should repeat at cycles 127, 254, etc.
                if (i % 127 != 0) begin
                    $display("ERROR: Unexpected repeat at cycle %0d", i);
                    error_count++;
                end
            end
        end
        
        if (repeat_count < 2) begin
            $display("ERROR: Sequence did not repeat properly in 300 cycles");
            error_count++;
        end
        enable = 0;
        
        // Test 7: Specific feedback scenarios
        // Both feedback bits are 1
        seed = 7'b1100000;  // bits 6 and 5 are both 1
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // Feedback = 1 XOR 1 = 0
        // Expected: 1000000
        if (lfsr_out !== 7'b1000000) begin
            $display("ERROR: Feedback with both bits=1 failed. Expected 1000000, got %b", lfsr_out);
            error_count++;
        end
        
        // Both feedback bits are 0
        seed = 7'b0011111;  // bits 6 and 5 are both 0
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // Feedback = 0 XOR 0 = 0
        // Expected: 0111110
        if (lfsr_out !== 7'b0111110) begin
            $display("ERROR: Feedback with both bits=0 failed. Expected 0111110, got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 8: Synchronous operation check
        // Verify that values are sampled at clock edge
        seed = 7'b0000111;
        load = 1;
        @(posedge clk);
        // Should load 0000111
        if (lfsr_out !== 7'b0000111) begin
            $display("ERROR: Synchronous operation failed. Expected 0000111, got %b", lfsr_out);
            error_count++;
        end
        load = 0;
        
        // Report results
        #10;
        if (error_count == 0) begin
            $display("@@@PASS");
        end else begin
            $display("@@@FAIL");
        end
        $finish();
    end
    
endmodule