module spi_tb (
    output logic        sclk,
    output logic        r_en,
    output logic        w_en,
    output logic [9:0]  addr,
    output logic [31:0] data_o,
    input  logic [31:0] data_i
);

    // Internal SPI signals for Main-to-Sub communication
    logic cs_n;
    logic mosi;
    logic miso;

    // Test signals
    logic [43:0] tx_data;
    logic [43:0] rx_data;
    integer error_count = 0;
    integer i;

    // Instantiate SPI Sub module (DUT)
    // Memory signals are passed through as outputs of this testbench
    spi_sub dut (
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso),
        .r_en(r_en),      // Pass through to testbench output
        .w_en(w_en),      // Pass through to testbench output
        .addr(addr),      // Pass through to testbench output
        .data_o(data_o),  // Pass through to testbench output
        .data_i(data_i)   // Pass through from testbench input
    );

    // Clock generation
    initial begin
        sclk = 0;
        forever #5 sclk = ~sclk;
    end

    // Task to send partial message
    task send_partial_message(input [43:0] message, input integer num_bits);
        begin
            tx_data = message;
            cs_n = 0;

            for (i = 43; i >= (44 - num_bits); i--) begin
                @(negedge sclk);
                mosi = tx_data[i];
                @(posedge sclk);
            end
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        cs_n = 1;
        mosi = 0;
        #20;

        // Test 1: Reset in middle of receive (after 20 bits)
        $display("Test 1: Reset during receive phase (20 bits)");
        send_partial_message({2'b01, 10'h111, 32'hAAAAAAAA}, 20);

        // Assert reset
        cs_n = 1;
        #20;

        // Verify no memory operation occurred
        if (w_en !== 1'b0 || r_en !== 1'b0) begin
            $display("ERROR: Memory operation triggered on incomplete message");
            error_count++;
        end

        // Verify miso returns to 0
        if (miso !== 1'b0) begin
            $display("ERROR: miso not 0 after reset");
            error_count++;
        end

        // Test 2: Reset just before last bit
        $display("Test 2: Reset just before last bit (43 bits)");
        send_partial_message({2'b00, 10'h222, 32'hBBBBBBBB}, 43);

        // Reset before bit 43 is received
        cs_n = 1;
        #20;

        // Verify no memory operation
        if (r_en !== 1'b0) begin
            $display("ERROR: Read triggered on incomplete 43-bit message");
            error_count++;
        end

        // Test 3: Reset during memory access phase
        $display("Test 3: Reset during memory access phase");
        cs_n = 0;
        tx_data = {2'b01, 10'h333, 32'hCCCCCCCC};

        // Send complete message
        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        // Wait for memory cycle to start
        @(posedge sclk);

        // Reset during memory access
        cs_n = 1;
        #10;

        // Memory signals should go low
        if (w_en !== 1'b0 || r_en !== 1'b0) begin
            $display("ERROR: Memory signals not cleared on reset");
            error_count++;
        end

        #10;

        // Test 4: Reset during transmit phase
        $display("Test 4: Reset during transmit phase");
        cs_n = 0;
        tx_data = {2'b01, 10'h444, 32'hDDDDDDDD};

        // Send complete message
        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        // Skip memory cycle
        @(posedge sclk);
        mosi = 0;

        // Start receiving response
        for (i = 43; i >= 30; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        // Reset in middle of response
        cs_n = 1;
        #20;

        // Verify miso goes to 0
        if (miso !== 1'b0) begin
            $display("ERROR: miso not 0 after reset during transmit");
            error_count++;
        end

        // Test 5: Quick reset and restart
        $display("Test 5: Quick reset and restart");
        cs_n = 0;

        // Send 10 bits
        for (i = 43; i >= 34; i--) begin
            @(negedge sclk);
            mosi = 1'b1;
            @(posedge sclk);
        end

        // Quick reset
        cs_n = 1;
        @(posedge sclk);
        @(posedge sclk);

        // Immediately start new transaction
        cs_n = 0;
        tx_data = {2'b01, 10'h555, 32'hEEEEEEEE};

        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        // Should complete normally
        @(posedge sclk);

        if (w_en !== 1'b1) begin
            $display("ERROR: Write not triggered after reset and restart");
            error_count++;
        end

        // Get response
        mosi = 0;
        for (i = 43; i >= 0; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        // Verify echo
        if (rx_data !== tx_data) begin
            $display("ERROR: Incorrect response after reset/restart");
            error_count++;
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 6: Reset timing - verify synchronous reset
        $display("Test 6: Verify synchronous reset");
        cs_n = 0;

        // Send a few bits
        for (i = 0; i < 5; i++) begin
            @(negedge sclk);
            mosi = 1'b1;
            @(posedge sclk);
        end

        // Assert cs_n between clock edges
        #3;  // Mid-cycle
        cs_n = 1;
        #2;  // Still before next edge

        // Reset should take effect on next posedge
        @(posedge sclk);

        // Verify reset took effect
        if (miso !== 1'b0) begin
            $display("ERROR: Reset not synchronous to clock");
            error_count++;
        end

        #20;

        // Test 7: Multiple resets
        $display("Test 7: Multiple consecutive resets");
        for (i = 0; i < 3; i++) begin
            cs_n = 0;
            @(posedge sclk);
            @(posedge sclk);
            cs_n = 1;
            @(posedge sclk);
        end

        // System should still work after multiple resets
        cs_n = 0;
        tx_data = {2'b00, 10'h666, 32'hFFFFFFFF};

        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        @(posedge sclk);

        if (r_en !== 1'b1) begin
            $display("ERROR: Read not working after multiple resets");
            error_count++;
        end

        // Final reset
        cs_n = 1;
        #20;

        // Report results
        if (error_count == 0) begin
            $display("@@@PASS");
        end else begin
            $display("@@@FAIL");
        end
        $finish();
    end

endmodule