`timescale 1ns/1ps

module soc_top_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic trap;

    // 100 MHz clock
    always #5 clk = ~clk;

    // Deassert reset after a few cycles
    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end

    soc_top #(
        .MEM_WORDS(32768),
        .HEX_PATH("firmware/peu_test/peu_test.hex")
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .trap  (trap)
    );

    initial begin : monitor
        int cycles = 0;
        wait (rst_n);
        forever begin
            @(posedge clk);
            cycles++;
            if (trap) begin
                $display("[%0t] Firmware completed after %0d cycles. PASS", $time, cycles);
                $finish;
            end
            if (cycles > 200_000) begin
                $fatal(1, "[%0t] Timeout waiting for trap. FAIL", $time);
            end
        end
    end
endmodule
