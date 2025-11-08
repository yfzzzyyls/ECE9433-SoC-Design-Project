module lfsr_tb_sequence;
    logic clk;
    logic reset;
    logic load;
    logic enable;
    logic [6:0] seed;
    logic [6:0] lfsr_out;
    
    integer error_count = 0;
    integer i, j;
    logic [6:0] sequence_buffer [0:127];
    logic [6:0] expected_values [0:10];
    logic [6:0] seen_values [0:126];
    
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
        
        // Test 1: Verify PDF example sequence
        // Seed = 7'b1100111, should produce specific sequence
        seed = 7'b1100111;
        load = 1;
        @(posedge clk);
        load = 0;
        
        // Set up expected values from PDF
        expected_values[0] = 7'b1100111;  // Initial
        expected_values[1] = 7'b1001110;  // After 1 shift
        expected_values[2] = 7'b0011101;  // After 2 shifts
        expected_values[3] = 7'b0111010;  // After 3 shifts
        expected_values[4] = 7'b1110101;  // After 4 shifts
        
        // Verify initial state
        if (lfsr_out !== expected_values[0]) begin
            $display("ERROR: Initial state wrong. Expected %b, got %b", expected_values[0], lfsr_out);
            error_count++;
        end
        
        // Verify first 4 shifts match PDF
        enable = 1;
        for (i = 1; i <= 4; i++) begin
            @(posedge clk);
            if (lfsr_out !== expected_values[i]) begin
                $display("ERROR: Cycle %0d wrong. Expected %b, got %b", i, expected_values[i], lfsr_out);
                error_count++;
            end
        end
        
        // Continue and verify 127-cycle periodicity
        // We already did 4 shifts, continue for remaining shifts
        // Total of 127 shifts should bring us back to initial seed
        for (i = 5; i <= 126; i++) begin
            @(posedge clk);
        end
        
        // After 127 shifts from initial, should return to initial seed
        @(posedge clk);
        if (lfsr_out !== 7'b1100111) begin
            $display("ERROR: Sequence did not repeat after 127 shifts. Expected 7'b1100111, got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 2: Test with all-ones seed (different from reset value path)
        seed = 7'b1111111;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        
        // Verify it produces valid sequence
        for (i = 0; i < 10; i++) begin
            @(posedge clk);
        end
        // After 10 shifts from all-ones, should have changed
        if (lfsr_out == 7'b1111111) begin
            $display("ERROR: LFSR stuck at all ones");
            error_count++;
        end
        enable = 0;
        
        // Test 3: Zero seed edge case - should stay at zero
        seed = 7'b0000000;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        
        for (i = 0; i < 10; i++) begin
            @(posedge clk);
            if (lfsr_out !== 7'b0000000) begin
                $display("ERROR: Zero seed should stay at zero. Got %b at cycle %0d", lfsr_out, i);
                error_count++;
                break;
            end
        end
        enable = 0;
        
        // Test 4: Another seed to verify PRBS7 pattern
        seed = 7'b0000001;
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        
        // Track that we get unique values (maximal length sequence)
        seen_values[0] = 7'b0000001;
        
        for (i = 1; i < 127; i++) begin
            @(posedge clk);
            seen_values[i] = lfsr_out;
            
            // Check this value hasn't been seen before
            for (j = 0; j < i; j++) begin
                if (seen_values[j] == lfsr_out && lfsr_out !== 7'b0000000) begin
                    $display("ERROR: Duplicate value %b seen at positions %0d and %0d (should be 127-cycle)", lfsr_out, j, i);
                    error_count++;
                    break;
                end
            end
        end
        
        // Should return to initial seed after 127 cycles
        @(posedge clk);
        if (lfsr_out !== 7'b0000001) begin
            $display("ERROR: Did not return to seed 0000001 after 127 cycles. Got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 5: Verify feedback calculation with specific pattern
        // Load a pattern where we know the feedback
        seed = 7'b1000000;  // bit6=1, bit5=0, feedback should be 1
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // After shift: should be 0000001
        if (lfsr_out !== 7'b0000001) begin
            $display("ERROR: Feedback calculation wrong. From 1000000, expected 0000001, got %b", lfsr_out);
            error_count++;
        end
        
        // Another feedback test
        seed = 7'b0100000;  // bit6=0, bit5=1, feedback should be 1
        load = 1;
        @(posedge clk);
        load = 0;
        enable = 1;
        @(posedge clk);
        // After shift: should be 1000001
        if (lfsr_out !== 7'b1000001) begin
            $display("ERROR: Feedback calculation wrong. From 0100000, expected 1000001, got %b", lfsr_out);
            error_count++;
        end
        
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