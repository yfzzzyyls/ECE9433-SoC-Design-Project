module lfsr_tb_basic;
    logic clk;
    logic reset;
    logic load;
    logic enable;
    logic [6:0] seed;
    logic [6:0] lfsr_out;
    
    integer error_count = 0;
    
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
        
        // Test 1: Reset functionality
        reset = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b1111111) begin
            $display("ERROR: Reset failed. Expected 7'b1111111, got %b", lfsr_out);
            error_count++;
        end
        reset = 0;
        
        // Test 2: Load functionality
        seed = 7'b1010101;
        load = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b1010101) begin
            $display("ERROR: Load failed. Expected 7'b1010101, got %b", lfsr_out);
            error_count++;
        end
        load = 0;
        
        // Test 3: Hold value when no control signals
        @(posedge clk);
        @(posedge clk);
        if (lfsr_out !== 7'b1010101) begin
            $display("ERROR: Hold failed. Expected 7'b1010101, got %b", lfsr_out);
            error_count++;
        end
        
        // Test 4: Enable shift operation
        enable = 1;
        @(posedge clk);
        // After shift: feedback = bit6 XOR bit5 = 1 XOR 0 = 1
        // Result should be: 0101011
        if (lfsr_out !== 7'b0101011) begin
            $display("ERROR: Shift failed. Expected 7'b0101011, got %b", lfsr_out);
            error_count++;
        end
        enable = 0;
        
        // Test 5: Priority - Reset > Load > Enable
        // All signals high, reset should win
        seed = 7'b0001111;
        reset = 1;
        load = 1;
        enable = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b1111111) begin
            $display("ERROR: Priority test 1 failed. Reset should override all. Got %b", lfsr_out);
            error_count++;
        end
        
        // Load > Enable (reset off)
        reset = 0;
        load = 1;
        enable = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b0001111) begin
            $display("ERROR: Priority test 2 failed. Load should override enable. Got %b", lfsr_out);
            error_count++;
        end
        
        // Test 6: Multiple loads with different seeds
        load = 1;
        enable = 0;
        seed = 7'b1100111;  // PDF example seed
        @(posedge clk);
        if (lfsr_out !== 7'b1100111) begin
            $display("ERROR: Load seed 1100111 failed. Got %b", lfsr_out);
            error_count++;
        end
        
        seed = 7'b0000001;
        @(posedge clk);
        if (lfsr_out !== 7'b0000001) begin
            $display("ERROR: Load seed 0000001 failed. Got %b", lfsr_out);
            error_count++;
        end
        load = 0;
        
        // Test 7: Consecutive shifts
        enable = 1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        enable = 0;
        // Just verify it changed from initial value
        if (lfsr_out == 7'b0000001) begin
            $display("ERROR: Multiple shifts failed. Value unchanged.");
            error_count++;
        end
        
        // Test 8: Reset after operations
        reset = 1;
        @(posedge clk);
        if (lfsr_out !== 7'b1111111) begin
            $display("ERROR: Final reset failed. Expected 7'b1111111, got %b", lfsr_out);
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