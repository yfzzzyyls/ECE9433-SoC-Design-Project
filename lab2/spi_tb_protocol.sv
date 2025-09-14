module spi_tb (
    output logic        sclk,
    output logic        r_en,
    output logic        w_en,
    output logic [9:0]  addr,
    output logic [31:0] data_o,
    input  logic [31:0] data_i
);

    // Internal SPI signals
    logic cs_n;
    logic mosi;
    logic miso;

    // Test signals
    logic [43:0] tx_data;
    logic [43:0] rx_data;
    integer error_count = 0;
    integer i;

    // Instantiate DUT
    spi_sub dut (
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso),
        .r_en(r_en),
        .w_en(w_en),
        .addr(addr),
        .data_o(data_o),
        .data_i(data_i)
    );

    // Clock generation
    initial begin
        sclk = 0;
        forever #5 sclk = ~sclk;
    end

    // Main test sequence for protocol-specific behaviors
    initial begin
        // Initialize
        cs_n = 1;
        mosi = 0;
        #20;

        // Test 1: Verify miso = 0 when cs_n = 1 (not high-Z)
        $display("Test 1: Verify miso = 0 when cs_n = 1 (idle)");
        cs_n = 1;
        #10;
        if (miso !== 1'b0) begin
            $display("ERROR: miso not 0 when cs_n = 1. Got %b", miso);
            error_count++;
        end

        // Test 2: No simultaneous transfers - miso = 0 during Main transmission
        $display("Test 2: Verify miso = 0 during Main transmission");
        cs_n = 0;
        tx_data = {2'b01, 10'h0AA, 32'h55AA55AA};

        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];

            // Check miso stays 0 during entire receive phase
            if (miso !== 1'b0) begin
                $display("ERROR: miso not 0 during receive at bit %d", i);
                error_count++;
                break;
            end
            @(posedge sclk);
        end

        // Now verify mosi = 0 during Sub response
        $display("Test 3: Verify mosi = 0 during Sub response");
        mosi = 0;  // Set to 0 for response phase

        // Skip memory cycle
        @(posedge sclk);

        for (i = 43; i >= 0; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;

            // Verify mosi stays 0
            if (mosi !== 1'b0) begin
                $display("ERROR: Test violated - mosi not 0 during response");
                error_count++;
            end
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 4: Verify exact 44-bit message length
        $display("Test 4: Verify exact 44-bit message protocol");
        cs_n = 0;

        // Send exactly 44 bits
        tx_data = {2'b00, 10'h123, 32'h89ABCDEF};
        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        // After 44 bits, memory operation should trigger
        @(posedge sclk);
        if (r_en !== 1'b1) begin
            $display("ERROR: r_en not asserted after exactly 44 bits");
            error_count++;
        end

        // Continue to receive exactly 44 bits response
        mosi = 0;
        for (i = 43; i >= 0; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        // Verify response format
        if (rx_data[43:42] !== 2'b00 || rx_data[41:32] !== 10'h123) begin
            $display("ERROR: Response header incorrect");
            error_count++;
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 5: MSB-first transmission verification
        $display("Test 5: Verify MSB-first transmission");
        cs_n = 0;

        // Send pattern with clear MSB/LSB difference
        tx_data = {2'b01, 10'b1000000001, 32'h80000001};  // MSB and LSB set

        for (i = 43; i >= 0; i--) begin
            @(negedge sclk);
            mosi = tx_data[i];
            @(posedge sclk);
        end

        // Get response
        @(posedge sclk);  // Memory cycle
        mosi = 0;

        for (i = 43; i >= 0; i--) begin
            @(posedge sclk);
            rx_data[i] = miso;
        end

        // Check echo matches (MSB first means bit 43 sent first)
        if (rx_data !== tx_data) begin
            $display("ERROR: MSB-first order not maintained. Sent %h, Got %h",
                     tx_data, rx_data);
            error_count++;
        end

        // Reset
        cs_n = 1;
        #20;

        // Test 6: Write echo vs Read data response
        $display("Test 6: Verify different response for Read vs Write");

        // First do a write
        cs_n = 0;
        tx_data = {2'b01, 10'h050, 32'hCAFEBABE};

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

        // Write should echo complete message
        if (rx_data !== tx_data) begin
            $display("ERROR: Write didn't echo message. Expected %h, Got %h",
                     tx_data, rx_data);
            error_count++;
        end

        cs_n = 1;
        #20;

        // Now read from same address
        cs_n = 0;
        tx_data = {2'b00, 10'h050, 32'hXXXXXXXX};

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

        // Read should return actual data, not echo
        if (rx_data[31:0] !== 32'hCAFEBABE) begin
            $display("ERROR: Read didn't return RAM data. Got %h", rx_data[31:0]);
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