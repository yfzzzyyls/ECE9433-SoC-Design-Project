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

    // Internal test signals
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

    // Task to send 44 bits on MOSI
    task send_spi_message(input [43:0] message);
        begin
            tx_data = message;
            cs_n = 0;  // Activate SPI

            // Send 44 bits MSB first
            for (i = 43; i >= 0; i--) begin
                @(negedge sclk);
                mosi = tx_data[i];
            end

            // Keep mosi at 0 during response
            @(negedge sclk);
            mosi = 0;
        end
    endtask

    // Task to receive 44 bits on MISO
    task receive_spi_response(output [43:0] response);
        begin
            rx_data = 44'b0;

            // Skip memory access cycle
            @(posedge sclk);

            // Receive 44 bits MSB first
            for (i = 43; i >= 0; i--) begin
                @(posedge sclk);
                rx_data[i] = miso;
            end

            response = rx_data;
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize signals
        cs_n = 1;
        mosi = 0;
        #20;

        // Test 1: Basic Write Operation
        // Write 0xDEADBEEF to address 0x10
        $display("Test 1: Write 0xDEADBEEF to address 0x10");
        send_spi_message({2'b01, 10'h010, 32'hDEADBEEF});
        receive_spi_response(rx_data);

        // Check echo response
        if (rx_data !== {2'b01, 10'h010, 32'hDEADBEEF}) begin
            $display("ERROR: Write echo mismatch. Expected %h, Got %h",
                     {2'b01, 10'h010, 32'hDEADBEEF}, rx_data);
            error_count++;
        end

        // Reset between transactions
        @(posedge sclk);
        cs_n = 1;
        #20;

        // Test 2: Basic Read Operation
        // Read from address 0x10 (should get 0xDEADBEEF)
        $display("Test 2: Read from address 0x10");
        send_spi_message({2'b00, 10'h010, 32'hXXXXXXXX});
        receive_spi_response(rx_data);

        // Check read response
        if (rx_data[43:32] !== {2'b00, 10'h010}) begin
            $display("ERROR: Read response header mismatch");
            error_count++;
        end
        if (rx_data[31:0] !== 32'hDEADBEEF) begin
            $display("ERROR: Read data mismatch. Expected DEADBEEF, Got %h", rx_data[31:0]);
            error_count++;
        end

        // Reset
        @(posedge sclk);
        cs_n = 1;
        #20;

        // Test 3: Write to different address
        $display("Test 3: Write 0x12345678 to address 0x20");
        send_spi_message({2'b01, 10'h020, 32'h12345678});
        receive_spi_response(rx_data);

        if (rx_data !== {2'b01, 10'h020, 32'h12345678}) begin
            $display("ERROR: Write echo mismatch for addr 0x20");
            error_count++;
        end

        // Reset
        @(posedge sclk);
        cs_n = 1;
        #20;

        // Test 4: Read from new address
        $display("Test 4: Read from address 0x20");
        send_spi_message({2'b00, 10'h020, 32'h00000000});
        receive_spi_response(rx_data);

        if (rx_data[31:0] !== 32'h12345678) begin
            $display("ERROR: Read data mismatch at addr 0x20. Expected 12345678, Got %h",
                     rx_data[31:0]);
            error_count++;
        end

        // Reset
        @(posedge sclk);
        cs_n = 1;
        #20;

        // Test 5: Verify first address still holds data
        $display("Test 5: Verify address 0x10 still has 0xDEADBEEF");
        send_spi_message({2'b00, 10'h010, 32'h00000000});
        receive_spi_response(rx_data);

        if (rx_data[31:0] !== 32'hDEADBEEF) begin
            $display("ERROR: Data at addr 0x10 was corrupted. Got %h", rx_data[31:0]);
            error_count++;
        end

        // Final reset
        @(posedge sclk);
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