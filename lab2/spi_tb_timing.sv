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
    integer cycle_count;

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

    // Task to verify timing requirements
    task verify_spi_timing();
        begin
            cycle_count = 0;

            // Start transaction
            cs_n = 0;

            // Send 44 bits and monitor timing
            for (i = 43; i >= 0; i--) begin
                @(negedge sclk);
                mosi = tx_data[i];  // Transmit on negedge
                cycle_count++;

                @(posedge sclk);
                // Sub should sample on posedge

                // Check critical timing points
                if (cycle_count == 44) begin
                    // After bit 43 sampled (Edge 8 in PDF)
                    // Next posedge should assert r_en or w_en
                    @(posedge sclk);
                    cycle_count++;

                    // Check memory signals (Edge 10 in PDF)
                    if (tx_data[43:42] == 2'b00 && r_en !== 1'b1) begin
                        $display("ERROR: r_en not asserted at correct time for read");
                        error_count++;
                    end
                    if (tx_data[43:42] == 2'b01 && w_en !== 1'b1) begin
                        $display("ERROR: w_en not asserted at correct time for write");
                        error_count++;
                    end

                    @(negedge sclk);
                    // This should be Edge 13 - start of transmission
                    // Verify miso starts changing
                    @(posedge sclk);
                    @(negedge sclk);

                    // Check that miso is transmitting
                    if (miso !== rx_data[43] && miso !== 1'bx) begin
                        $display("ERROR: MISO not transmitting at expected time");
                        error_count++;
                    end
                end
            end

            // Continue receiving response
            mosi = 0;  // Main must hold mosi = 0 during response

            for (i = 43; i >= 0; i--) begin
                @(posedge sclk);
                rx_data[i] = miso;
            end
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        cs_n = 1;
        mosi = 0;
        tx_data = 44'b0;
        rx_data = 44'b0;
        #20;

        // Test 1: Verify write timing
        $display("Test 1: Verify write operation timing");
        tx_data = {2'b01, 10'h055, 32'hAABBCCDD};
        verify_spi_timing();

        // Check that r_en/w_en go low after one cycle
        @(posedge sclk);
        if (w_en !== 1'b0) begin
            $display("ERROR: w_en not deasserted after one cycle");
            error_count++;
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 2: Verify read timing
        $display("Test 2: Verify read operation timing");
        tx_data = {2'b00, 10'h055, 32'h00000000};
        verify_spi_timing();

        @(posedge sclk);
        if (r_en !== 1'b0) begin
            $display("ERROR: r_en not deasserted after one cycle");
            error_count++;
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 3: Verify miso behavior during receive
        $display("Test 3: Verify miso = 0 during receive phase");
        cs_n = 0;

        for (i = 0; i < 44; i++) begin
            @(negedge sclk);
            mosi = 1'b1;

            // Check miso stays 0 during receive
            if (miso !== 1'b0) begin
                $display("ERROR: miso not 0 during receive at bit %d", i);
                error_count++;
                break;
            end

            @(posedge sclk);
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 4: Verify posedge sampling
        $display("Test 4: Verify data sampled on posedge");
        cs_n = 0;

        // Send pattern that changes on negedge
        for (i = 0; i < 44; i++) begin
            @(negedge sclk);
            mosi = (i % 2);  // Alternating pattern

            @(posedge sclk);
            // Sub should sample here
        end

        // Skip to response and check pattern was received
        @(posedge sclk);
        @(negedge sclk);

        // Get first few bits of response
        for (i = 43; i >= 40; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        // For write (01), first two bits should be 01
        if (rx_data[43:42] !== 2'b01) begin
            $display("ERROR: Incorrect sampling detected in response");
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