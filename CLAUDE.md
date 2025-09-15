# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NYU ECE9433 Fall 2025 SoC Design course project repository containing SystemVerilog implementations for digital design labs.

## Repository Structure

```
ECE9433-SoC-Design-Project/
├── lab1/                  # Lab 1: LFSR implementation
│   ├── lfsr.sv           # Main LFSR design
│   ├── lfsr_tb_*.sv      # Multiple testbenches
│   └── simv              # Compiled simulation executable
├── lab2/                  # Lab 2: SPI submodule
│   ├── spi_sub.sv        # SPI submodule implementation
│   ├── spi_tb_*.sv       # Multiple testbenches
│   ├── ram.sv            # Memory module
│   ├── tb_top.sv         # Top-level testbench wrapper
│   └── simv              # Compiled simulation executable
└── README.md
```

## Build and Test Commands

### Compiling SystemVerilog Code
VCS (Synopsys VCS simulator) is used for compilation and simulation:

```bash
# Compile in lab directory (creates simv executable)
cd lab1/  # or lab2/
vcs -sverilog -debug_all +v2k *.sv

# Run simulation
./simv

# Run specific testbench (Lab 2)
./simv +TB=basic    # Run basic tests
./simv +TB=protocol # Run protocol tests
./simv +TB=timing   # Run timing tests
./simv +TB=stress   # Run stress tests
./simv +TB=reset    # Run reset tests
```

### Clean Build Artifacts
```bash
# Clean VCS artifacts
rm -rf csrc/ simv simv.daidir/ ucli.key verdi_config_file
```

## Testing Architecture

### Lab 1: LFSR
- Testbenches must use blackbox testing (no internal signal access)
- All testbenches must print exactly one `@@@PASS` or `@@@FAIL`
- Test coverage: reset behavior, load functionality, enable control, PRBS7 sequence

### Lab 2: SPI Submodule
- Uses `tb_top.sv` wrapper that instantiates student testbench and RAM
- Multiple specialized testbenches for different aspects:
  - `spi_tb_basic.sv`: Basic read/write operations
  - `spi_tb_protocol.sv`: Protocol compliance testing
  - `spi_tb_timing.sv`: Timing verification
  - `spi_tb_stress.sv`: Stress testing with multiple operations
  - `spi_tb_reset.sv`: Reset behavior testing
- Testbench must implement `spi_tb` module interface matching `tb_top.sv`

## Development Environment

- **Simulator**: Synopsys VCS U-2023.03-SP2-5
- **Language**: SystemVerilog
- **Python Environment**: Use conda for any Python-based tools
  ```bash
  source ~/miniconda3/bin/activate
  ```

## Lab 1: PRBS7 Linear Feedback Shift Register

### Requirements
- Implement a 7-bit LFSR following PRBS7 specification (polynomial: x⁷ + x⁶ + 1)
- XOR bits D6 and D5, left shift register, insert XOR result into D0
- Generates 127-bit pseudo-random sequence before repeating
- All operations synchronous to clock

### Module Interface
```systemverilog
module lfsr (
    input logic clk,
    input logic reset,     // active-high sync reset to 7'b1111111
    input logic load,      // load seed value
    input logic enable,    // enable LFSR shift operation
    input logic [6:0] seed,
    output logic [6:0] lfsr_out
);
```

### Control Signal Priority
1. `reset` (highest) - sets register to all 1s
2. `load` - loads seed value into register
3. `enable` (lowest) - performs LFSR shift operation
4. If no signals asserted, maintain current value

### Files to Submit
- `lfsr.sv` - main design implementation
- `lfsr_tb_*.sv` - one or more testbenches (blackbox testing only)

### Testbench Requirements
- Must print `@@@PASS` or `@@@FAIL` exactly once
- Cannot access internal signals of DUT (blackbox testing)
- Test all specification requirements to catch buggy designs

## Lab 2: SPI Submodule Implementation

### Overview
Implement an SPI submodule that communicates with a main controller using a custom 44-bit protocol:
- Protocol: `[Op:2][Addr:10][Data:32]` (MSB first)
- Op codes: `00` = READ, `01` = WRITE
- SPI Mode 0: Sample on rising edge, change on falling edge
- 4-state FSM: IDLE → RECEIVE → MEMORY → TRANSMIT → IDLE

### Key Issues Encountered and Solutions

#### 1. **Testbench Architecture Issues**
**Problem**: Module port mismatches between `spi_tb` and `tb_top.sv`
- **Attempted**: Creating standalone testbench without ports
- **Solution**: Keep testbench ports to work with `tb_top.sv` wrapper

#### 2. **Race Conditions and Multiple Drivers**
**Problem**: Signals driven in both posedge and negedge blocks
- **Attempted**:
  - Driving `tx_cnt` and `tx_arm` in both posedge and negedge blocks
  - Complex signal handoff mechanisms
- **Solution**: Drive each signal in only one always block
  - `tx_cnt`, `tx_arm` managed in posedge block only
  - `miso` managed in negedge block only

#### 3. **RX Sampling Timing (SOLVED)**
**Problem**: Missing first bit (bit[43]) during receive
- **Root Cause**: State machine transitions from IDLE→RECEIVE on same posedge that needs to sample first bit
- **Attempted**:
  - Sampling when `state == IDLE && !cs_n`
  - Adding delays in testbench
- **Working Solution**: Sample when `next_state == RECEIVE || state == RECEIVE`
  - This catches the transition cycle where first bit arrives

#### 4. **Message Field Extraction (SOLVED)**
**Problem**: Wrong addresses and data being extracted (addresses doubled, data corrupted)
- **Root Cause**: Extracting fields from shift register instead of complete message
- **Initial Buggy Code**:
  ```systemverilog
  op_code <= rx_shift_reg[42:41];  // Wrong!
  addr_reg <= rx_shift_reg[40:31]; // Wrong!
  ```
- **Working Solution**:
  ```systemverilog
  logic [43:0] complete_msg = {rx_shift_reg[42:0], mosi};
  op_code <= complete_msg[43:42];
  addr_reg <= complete_msg[41:32];
  data_reg <= complete_msg[31:0];
  ```

#### 5. **Memory Access Timing (SOLVED)**
**Problem**: Memory operations not happening at the right time
- **Solution**: Use combinational enables during MEMORY state
  ```systemverilog
  // Combinational assignment for immediate response
  assign r_en = (state == MEMORY) && (op_code == 2'b00);
  assign w_en = (state == MEMORY) && (op_code == 2'b01);
  ```

#### 6. **TX Response Timing - MAJOR BREAKTHROUGH (SOLVED)**
**Problem**: TX response had 1-bit right shift (missing MSB)
- Expected: `0x410deadbeef`
- Got: `0x2086f56df77` (exactly half, right-shifted by 1)

**Root Cause Analysis**:
1. During MEMORY state, `tx_shift_reg` is loaded on posedge but `data_i` from RAM isn't available yet
2. The first bit needs to be output on the negedge of the MEMORY state
3. But `tx_shift_reg` doesn't have the correct data until the next posedge
4. This created a chicken-and-egg timing problem

**The Breakthrough Solution**:
```systemverilog
// 1. Make memory enables combinational for immediate RAM response
assign r_en = (state == MEMORY) && (op_code == 2'b00);
assign w_en = (state == MEMORY) && (op_code == 2'b01);

// 2. Create combinational TX data that's immediately available
always_comb begin
  if (op_code == 2'b00) begin
    tx_data = {message[43:32], data_i};  // READ: op+addr from message, data from RAM
  end else begin
    tx_data = message;  // WRITE: echo entire message
  end
end

// 3. Split MISO output logic based on state
always_ff @(negedge sclk) begin
  if (cs_n) begin
    miso <= 1'b0;
  end else if (state == MEMORY) begin
    // During MEMORY: use combinational tx_data (available immediately)
    miso <= tx_data[43];  // Output bit 43 directly
  end else if (state == TRANSMIT) begin
    // During TRANSMIT: use registered tx_shift_reg
    miso <= tx_shift_reg[43 - tx_bit_count];
  end
end

// 4. Adjust bit counter to account for first bit sent during MEMORY
always_ff @(posedge sclk) begin
  if (state == MEMORY) begin
    tx_shift_reg <= tx_data;
    tx_bit_count <= 6'd1;  // Start at 1 since bit[43] output during MEMORY
  end
end
```

**Why This Works**:
- Combinational memory enables ensure `data_i` is available immediately when entering MEMORY state
- Combinational `tx_data` preparation means the correct TX data is ready without waiting for a clock edge
- Splitting MISO logic allows using combinational data during MEMORY and registered data during TRANSMIT
- This ensures bit[43] is output on the first negedge after entering MEMORY state, exactly when the testbench expects it

### Current State
- **Working**:
  - ✅ RX path correctly receives all 44 bits
  - ✅ Memory writes and reads work correctly (correct addresses and data)
  - ✅ State machine transitions properly
  - ✅ TX response timing fixed - no more 1-bit shift!
  - ✅ Basic testbench passes completely

### Test Results After Fix:
```
=== Test 1: Write 0xDEADBEEF to address 0x010 ===
DEBUG: Write enable at time 505000, addr=010, data=deadbeef
PASS: Write echo correct

=== Test 2: Read from address 0x010 ===
DEBUG: Read enable at time 1425000, addr=010, data_i=deadbeef
PASS: Read data correct

=== Test Summary ===
All tests passed!
@@@PASS
```

### Key Timing Requirements
1. **RX**: Sample on posedge, shift in MSB first
2. **Memory**: One-cycle access during MEMORY state
3. **TX**: Drive on negedge, MSB first, start immediately after memory access
4. **Testbench Expectation**: After sending 44 bits, waits 1 posedge (memory cycle), then samples 44 bits

### Lessons Learned
1. **Avoid Multiple Drivers**: Each signal should be driven by exactly one always block
2. **Consider State Transitions**: Use `next_state` for combinational checks when state hasn't updated yet
3. **Complete Message Assembly**: Extract fields after assembling the complete message, not from intermediate shift registers
4. **Timing Analysis**: Draw detailed waveforms to understand exact cycle-by-cycle behavior
5. **Combinational vs Sequential Logic**: When you need immediate response (like RAM data for TX), use combinational logic
6. **Split Complex Operations**: Separate combinational data preparation from sequential state updates
7. **The Power of Combinational Bypass**: Sometimes you need combinational paths to meet timing requirements, especially when data from one block (RAM) needs to be immediately available to another (TX output)

## Critical SystemVerilog Rules for This Course

### NEVER Use Timescale Directives
**IMPORTANT**: Do NOT use `timescale` directives in SystemVerilog files for this course.
- Timescale directives (e.g., `timescale 1ns/1ps`) cause autograder failures
- The autograder will fail with cryptic errors like "/bin/sh: 0: Illegal option -h"
- VCS compilation and local simulation work fine without timescale directives
- All timing is handled by the simulator defaults
- This rule was explicitly stated by the instructor and confirmed through debugging

Example of what NOT to do:
```systemverilog
`timescale 1ns/1ps  // DO NOT USE THIS!
module spi_sub (...);
```

Correct approach:
```systemverilog
// No timescale directive
module spi_sub (...);
