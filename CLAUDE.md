# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the NYU ECE9433 Fall 2025 SoC Design course project repository. Currently contains Lab1 materials focused on LFSR (Linear Feedback Shift Register) implementation.

## Repository Structure

```
ECE9433-SoC-Design-Project/
├── Lab1/                  # Lab 1 assignment materials
│   └── course_ece9433_assignment_lab1_lfsr.pdf
├── LICENSE               # MIT License
└── README.md            # Basic project description
```

## Development Notes

- This appears to be an academic SoC design project repository in its initial stages
- Lab1 focuses on LFSR implementation based on the PDF assignment
- No source code files have been implemented yet
- The repository uses Git for version control with main branch as the primary branch

## Development Environment

- Use conda environment for Python-based tools and simulations
- Activate conda before running Python scripts:
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
- **Solution**: Use registered enables during MEMORY state
  ```systemverilog
  if (state == MEMORY) begin
    r_en <= (op_code == 2'b00);
    w_en <= (op_code == 2'b01);
  end
  ```

#### 6. **TX Response Timing (CURRENT ISSUE)**
**Problem**: TX response has 1-bit right shift (missing MSB)
- Expected: `0x410deadbeef`
- Got: `0x2086f56df77` (exactly half, right-shifted by 1)
- **Root Cause**: First bit (bit[43]) not transmitted at the right time
- **Attempted Solutions**:
  1. `tx_armed` flag mechanism - race conditions between posedge/negedge
  2. Checking `next_state == TRANSMIT` - outputs too early
  3. Complex bit counter management - didn't fix timing
  4. Using `mem_access_en` flag - still not working
- **Issue**: Timing mismatch between when TX starts and when testbench expects first bit

### Current State
- **Working**:
  - RX path correctly receives all 44 bits
  - Memory writes and reads work correctly (correct addresses and data)
  - State machine transitions properly
- **Not Working**:
  - TX response shifted by 1 bit (missing MSB)
  - All test failures are due to this TX timing issue

### Debug Output Shows:
```
DEBUG: Write enable at time 525000, addr=010, data=deadbeef  ✓ (correct)
DEBUG: Read enable at time 1445000, addr=010, data_i=deadbeef ✓ (correct)
ERROR: Write echo mismatch - Expected: 410deadbeef Got: 2086f56df77 ✗ (1-bit shift)
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
5. **Simplify First**: Start with simple solutions before adding complex mechanisms
