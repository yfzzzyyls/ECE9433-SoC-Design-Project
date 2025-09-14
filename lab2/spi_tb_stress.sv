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
    integer i, j;
    logic [31:0] test_data;
    logic [9:0] test_addr;

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

    // Task for complete SPI transaction
    task spi_transaction(input [1:0] op, input [9:0] addr_in,
                         input [31:0] data_in, output [43:0] response);
        begin
            // Prepare message
            tx_data = {op, addr_in, data_in};
            cs_n = 0;

            // Send 44 bits
            for (i = 43; i >= 0; i--) begin
                @(negedge sclk);
                mosi = tx_data[i];
                @(posedge sclk);
            end

            // Memory access cycle
            @(posedge sclk);
            mosi = 0;

            // Receive 44 bits response
            for (i = 43; i >= 0; i--) begin
                @(posedge sclk);
                rx_data[i] = miso;
            end

            response = rx_data;

            // Reset
            @(posedge sclk);
            cs_n = 1;
            @(posedge sclk);
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        cs_n = 1;
        mosi = 0;
        #20;

        // Test 1: Back-to-back writes
        $display("Test 1: Back-to-back write operations");
        for (j = 0; j < 10; j++) begin
            test_addr = j * 8;  // Addresses 0, 8, 16, 24, ...
            test_data = 32'hA0000000 + j;

            spi_transaction(2'b01, test_addr, test_data, rx_data);

            // Verify echo
            if (rx_data !== {2'b01, test_addr, test_data}) begin
                $display("ERROR: Write %d echo mismatch", j);
                error_count++;
            end
        end

        // Test 2: Back-to-back reads
        $display("Test 2: Back-to-back read operations");
        for (j = 0; j < 10; j++) begin
            test_addr = j * 8;

            spi_transaction(2'b00, test_addr, 32'h00000000, rx_data);

            // Verify data matches what was written
            if (rx_data[31:0] !== (32'hA0000000 + j)) begin
                $display("ERROR: Read %d data mismatch. Expected %h, Got %h",
                         j, (32'hA0000000 + j), rx_data[31:0]);
                error_count++;
            end
        end

        // Test 3: Alternating read/write
        $display("Test 3: Alternating read/write operations");
        for (j = 0; j < 20; j++) begin
            test_addr = 10'h100 + j;

            if (j % 2 == 0) begin
                // Write
                test_data = 32'hB0000000 | j;
                spi_transaction(2'b01, test_addr, test_data, rx_data);

                if (rx_data !== {2'b01, test_addr, test_data}) begin
                    $display("ERROR: Alternating write %d failed", j);
                    error_count++;
                end
            end else begin
                // Read previous write
                spi_transaction(2'b00, test_addr - 1, 32'h00000000, rx_data);

                if (rx_data[31:0] !== (32'hB0000000 | (j-1))) begin
                    $display("ERROR: Alternating read %d failed", j);
                    error_count++;
                end
            end
        end

        // Test 4: Minimum gap between transactions
        $display("Test 4: Minimum gap between transactions");
        for (j = 0; j < 5; j++) begin
            // Start transaction
            cs_n = 0;
            tx_data = {2'b01, 10'h200 + j, 32'hC0000000 | j};

            // Send message
            for (i = 43; i >= 0; i--) begin
                @(negedge sclk);
                mosi = tx_data[i];
                @(posedge sclk);
            end

            @(posedge sclk);
            mosi = 0;

            // Receive response
            for (i = 43; i >= 0; i--) begin
                @(posedge sclk);
                rx_data[i] = miso;
            end

            // Minimal reset - just one cycle
            cs_n = 1;
            @(posedge sclk);
            // Immediately start next transaction (no extra delay)
        end

        // Verify last write worked
        cs_n = 0;
        tx_data = {2'b00, 10'h204, 32'h00000000};

        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        @(posedge sclk);
        mosi = 0;

        for (i = 43; i >= 0; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        if (rx_data[31:0] !== 32'hC0000004) begin
            $display("ERROR: Minimum gap test failed");
            error_count++;
        end

        cs_n = 1;
        #20;

        // Test 5: Full address range
        $display("Test 5: Testing address boundaries");

        // Test address 0x000
        spi_transaction(2'b01, 10'h000, 32'h11111111, rx_data);
        spi_transaction(2'b00, 10'h000, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'h11111111) begin
            $display("ERROR: Address 0x000 failed");
            error_count++;
        end

        // Test address 0x0FF (255 - near max for 8-bit)
        spi_transaction(2'b01, 10'h0FF, 32'h22222222, rx_data);
        spi_transaction(2'b00, 10'h0FF, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'h22222222) begin
            $display("ERROR: Address 0x0FF failed");
            error_count++;
        end

        // Test 6: Data patterns
        $display("Test 6: Various data patterns");

        // All zeros
        spi_transaction(2'b01, 10'h080, 32'h00000000, rx_data);
        spi_transaction(2'b00, 10'h080, 32'hFFFFFFFF, rx_data);
        if (rx_data[31:0] !== 32'h00000000) begin
            $display("ERROR: All zeros pattern failed");
            error_count++;
        end

        // All ones
        spi_transaction(2'b01, 10'h081, 32'hFFFFFFFF, rx_data);
        spi_transaction(2'b00, 10'h081, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'hFFFFFFFF) begin
            $display("ERROR: All ones pattern failed");
            error_count++;
        end

        // Alternating bits
        spi_transaction(2'b01, 10'h082, 32'hAAAAAAAA, rx_data);
        spi_transaction(2'b00, 10'h082, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'hAAAAAAAA) begin
            $display("ERROR: Alternating pattern 0xAAAAAAAA failed");
            error_count++;
        end

        spi_transaction(2'b01, 10'h083, 32'h55555555, rx_data);
        spi_transaction(2'b00, 10'h083, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'h55555555) begin
            $display("ERROR: Alternating pattern 0x55555555 failed");
            error_count++;
        end

        // Test 7: Continuous operation for extended time
        $display("Test 7: Extended continuous operation");
        for (j = 0; j < 50; j++) begin
            test_addr = (j * 3) & 10'h0FF;  // Wrap around
            test_data = j * 32'h01010101;

            // Write
            spi_transaction(2'b01, test_addr, test_data, rx_data);

            // Immediate read back
            spi_transaction(2'b00, test_addr, 32'h00000000, rx_data);

            if (rx_data[31:0] !== test_data) begin
                $display("ERROR: Extended operation %d failed", j);
                error_count++;
                if (error_count > 10) break;  // Stop if too many errors
            end
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