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
