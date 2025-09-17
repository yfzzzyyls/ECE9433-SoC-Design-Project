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

### Professor's Critical Hints and Feedback

#### Initial Hint (Dec 2024)
**Focus on Section 4.3 of the specification PDF**, especially understanding the edge timing. If your waveform matches exactly what Section 4.3 shows, you should get it correct. The key edges from the clarification:
- **Edge 8**: Last bit sampled by sub (posedge)
- **Edge 10**: Memory pulse - w_en/r_en asserted (next posedge after last bit)
- **Edge 13**: MISO starts transmitting (following negedge after memory pulse)
- Important: MISO starting at edge 13 doesn't mean it changes from 0 to 1 - it means transmission begins, even if first bit is 0

#### General Tips Email (Dec 2024)
Professor's email about common issues:
```
Hi all,

Here are general tips from questions that keep coming up from students:

1. One of the first things you should be doing is making sure that your testbench is valid. If you testbench does not pass the validity check, it means it is testing for behavior that is out of line with the specification. You can't expect your design to be correct if it conforms to tests that are incorrect. (It could also mean a compilation error. Be sure you do not have `timescale in your testbench)

2. Please read the assignment specification carefully. We try our best to make sure the specification is clearly defined and that it resolves all questions about how the design should operate.

3. Please look closely at the waveform diagrams and the example VCD file. Several students have asked why their design and/or testbench is failing, and they haven't tried reproducing the example waveform file provided.

4. Most students' problems have been off-by-one errors where they add in extra delays. This causes the message to be corrupted, because it deviates from the specification.

5. If you read from an address that was not previously written to, the returned data is undefined. We don't test for this behavior, and you should not try testing for it.

Best,
Austin
```

#### Specific Feedback on Testbench Timing Issues
Professor's response to debugging request with waveform analysis:

**Issue 1: Wrong bits being transmitted**
```
It looks like you are trying to do a write operation to address 0x100 with the data 0x9A364721. But from the first few bits transmitted I can see that you are transmitting 001010... which doesn't match up with the string you are trying to send. The first 00 causes the message to be a read message, not a write message, which messes up the rest of the transaction and your testbench therefore reports a failure.
```

**Issue 2: Extra negedge delays**
```
I think in your testbench, the following line is causing an extra negedge to be added for every transaction. This delays the signal by 1 cycle and causes the wrong bits to be sent. Please look at the figures in the spec very carefully and make sure you are sending the correct bits on the correct edges.

In this for loop, the negedge comes first so you are also adding another cycle of delay before the signal gets updated. Please check that you are not delaying the signals that you are trying to transmit.
```

**Critical testbench timing requirements:**
1. Bits must start being sent immediately from the first posedge sclk after cs_n goes low
2. Bits must be sent in MSB order
3. No extra negedge delays before asserting cs_n
4. First bit must be on MOSI when cs_n is asserted

### Mutation Testing Rules (Lab 2 Autograder)

#### Overview
The autograder uses mutation testing to verify testbench quality. Your testbenches must catch bugs in mutated (buggy) designs while correctly passing the instructor's correct design.

#### Key Rules
1. **Multiple Testbenches Allowed**: You can submit multiple testbenches (e.g., `spi_tb_basic.sv`, `spi_tb_protocol.sv`, etc.)
2. **False Positive Prevention**: Each testbench is first run against the correct instructor design
   - If a testbench reports `@@@FAIL` on the correct design → testbench is IGNORED (false positive)
   - Only testbenches that report `@@@PASS` on correct design are considered valid
3. **Bug Detection**: Valid testbenches are run against each buggy/mutated design
   - If ANY valid testbench reports `@@@FAIL` on a buggy design → you get the point for catching that bug
4. **Targeted Testing Strategy**: Different testbenches can test different behaviors
   - You don't need one testbench to catch all bugs
   - Can have specialized testbenches for specific functionality
5. **Scoring**: To get full points, your combined testbenches must catch ALL bugs
6. **No Debug Output**: Mutation tests only show pass/fail results, no logs or detailed output

#### Testing Strategy
- Create multiple focused testbenches, each targeting specific behaviors:
  - Basic read/write operations
  - Protocol compliance (timing, bit order)
  - Edge cases (reset, back-to-back transactions)
  - Memory interface correctness
  - Response format validation
- Each testbench MUST pass the correct design (avoid false positives)
- Together, testbenches should cover all possible bugs

### Lessons Learned
1. **Avoid Multiple Drivers**: Each signal should be driven by exactly one always block
2. **Consider State Transitions**: Use `next_state` for combinational checks when state hasn't updated yet
3. **Complete Message Assembly**: Extract fields after assembling the complete message, not from intermediate shift registers
4. **Timing Analysis**: Draw detailed waveforms to understand exact cycle-by-cycle behavior
5. **Combinational vs Sequential Logic**: When you need immediate response (like RAM data for TX), use combinational logic
6. **Split Complex Operations**: Separate combinational data preparation from sequential state updates
7. **The Power of Combinational Bypass**: Sometimes you need combinational paths to meet timing requirements, especially when data from one block (RAM) needs to be immediately available to another (TX output)
8. **Testbench Timing is Critical**: Off-by-one errors from extra delays are the most common cause of failures
9. **Don't Test Undefined Behavior**: Never test reads from unwritten addresses - the data is undefined
10. **Follow Specification Exactly**: The waveform diagrams and VCD files show the exact required behavior

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
```

### Testbench False Positive Notes

**IMPORTANT**: The following testbenches are known to cause false positives on the autograder:
- `spi_tb_signals.sv` - Fails on correct design despite testing valid behavior
- `spi_tb_timing.sv` - Fails on correct design despite testing valid behavior

These testbenches should NOT be submitted to the autograder as they will be ignored due to false positive detection.

### Ultimate Testbench: spi_tb_all.sv

**BREAKTHROUGH**: The `spi_tb_all.sv` testbench successfully catches ALL 5 bugs in the autograder mutation testing.

#### Why spi_tb_all.sv Catches All Bugs

This testbench combines multiple critical test patterns in a specific sequence that exposes all mutation bugs:

1. **Precise Timing Control**: Uses `#2` delay after negedge before cs_n assertion
   - Ensures proper setup timing that many buggy designs violate

2. **Sequential Address Pattern**: Tests two consecutive addresses (0x35, then 0x34)
   - Catches address decoding bugs and off-by-one errors

3. **Back-to-back Writes Without CS_N Deassertion**:
   - First write to addr 0x35 with data 0xCAFEBABE
   - Second write to addr 0x34 with same data
   - No cs_n toggle between them - tests continuous operation

4. **State Machine Reset Testing**:
   - Deasserts cs_n after writes, before read
   - Ensures state machine properly resets

5. **Cross-Address Data Verification**:
   - Writes to both 0x35 and 0x34
   - Reads only from 0x34
   - Verifies correct address handling and data persistence

6. **Complete Response Validation**:
   - Checks all fields: opcode, address, and data
   - Write echo must match exactly
   - Read response must have correct format

The key insight: This specific sequence (write A11 → write A10 → deassert CS → read A10) creates a test pattern that simultaneously stresses multiple aspects of the design that individual focused testbenches miss.

### Recommended Testbenches for Submission (10 total)

**Primary testbench** (catches all 5 bugs):
1. `spi_tb_all.sv` - Comprehensive test catching all bugs

**Supporting testbenches** (for redundancy):
2. `spi_tb_basic.sv` - Minimal test with simple write operation
3. `spi_tb_write.sv` - Write echo functionality
4. `spi_tb_readwrite.sv` - Write-then-read data persistence
5. `spi_tb_boundaries.sv` - Edge cases (0x000, 0x3FF, all 0s/1s)
6. `spi_tb_opcodes.sv` - All operation codes
7. `spi_tb_bitpatterns.sv` - Walking 1s and shift patterns
8. `spi_tb_addrmask.sv` - 10-bit address masking/wraparound
9. `spi_tb_response.sv` - Response format verification
10. `spi_tb_protocol.sv` - Protocol compliance testing

## CRITICAL LESSON: Why Sequential Architectures Failed in SPI Design

### The Fundamental Architectural Flaw We Discovered

After countless hours debugging `spi_sub_old.sv`, we learned that **architecture determines capability - you cannot patch fundamental architectural flaws with local optimizations**.

#### Our Failed Sequential Architecture (spi_sub_old.sv):
```
IDLE → RECEIVE → MEMORY → TRANSMIT
```
- Each state must complete before the next begins
- MEMORY state loads `tx_reg` on posedge
- TRANSMIT state outputs `miso` on negedge
- **Fatal flaw**: One full clock cycle delay between memory access and first TX bit

#### The Working Parallel Architecture (spi_sub.sv):
```
IDLE → RECV → ACCESS → RESP (with cross-domain handshaking)
```
- Uses `arm_resp` flag for immediate cross-domain signaling
- Negedge block responds instantly to posedge events
- **Success**: First TX bit appears on the exact negedge required

### The Key Innovation: Cross-Domain Handshaking

The golden design's secret weapon that we missed:
```systemverilog
// Posedge domain sets flag:
arm_resp <= 1'b1;  // Signal ready

// Negedge domain responds immediately:
if (arm_resp) begin
  tx_shift <= {op_l, ad_l, da_l};
  miso_q <= {op_l, ad_l, da_l}[43];  // Output first bit NOW
end
```

### What We Did Wrong

1. **Thinking Sequentially**: We assumed MEMORY must finish → then TRANSMIT starts
2. **Missing Parallelism**: The spec requires memory access and TX start to overlap
3. **Patching Symptoms**: We tried combinational bypasses, timing adjustments, bit counter tricks
4. **Ignoring Architecture**: We never questioned if sequential states could meet the timing

### The Ultimate Lesson

> **When facing persistent timing bugs, don't just debug harder - step back and question the architecture.**

Hardware isn't software. Timing requirements often demand parallel, cross-domain solutions that feel less intuitive but meet strict specifications. Our "logical" sequential design was fundamentally incapable of meeting the spec's timing requirements.

### Key Takeaways for Future Designs

1. **Recognize timing requirements early**: If the spec shows operations overlapping, design for parallelism
2. **Use cross-domain signaling**: Handshaking between clock domains enables immediate response
3. **Name states meaningfully**: ACCESS/RESP implies parallelism; MEMORY/TRANSMIT implies sequence
4. **Architecture first, optimization second**: Get the fundamental structure right before fine-tuning

