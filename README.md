# ECE9433-SoC-Design-Project
NYU ECE9433 Fall2025 SoC Design Project
Author:
Zhaoyu Lu
Jiaying Yong
Fengze Yu

## Third-Party IP

### Quick setup

```bash
./setup.sh
```

The script fetches the PicoRV32 core from the official YosysHQ repository and drops it into `third_party/picorv32/`. Re-run it any time you want to sync to the pinned revision.

## RISC-V Toolchain Setup

We rely on the xPack bare-metal toolchain (`riscv-none-elf-*`) so everyone builds with the same compiler version.

1. Download and extract the archive (Linux x86_64 example):
```bash
cd /path/to/ECE9433-SoC-Design-Project/third_party
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
tar -xf xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
mv xpack-riscv-none-elf-gcc-15.2.0-1 riscv-toolchain
```

2. Add the binaries to your PATH (place this in `.bashrc`/`.zshrc`):
   ```bash
   export PATH="/path/to/ECE9433-SoC-Design-Project/third_party/riscv-toolchain/bin:$PATH"
   ```

3. Verify the compiler:
   ```bash
   which riscv-none-elf-gcc
   ```

If you prefer a different xPack release, swap in the desired tag but keep the extracted directory name `riscv-toolchain` so the path stays consistent across machines.

## Building the Reference Firmware

After the toolchain and PicoRV32 sources are in place:

```bash
cd /path/to/ECE9433-SoC-Design-Project/third_party/picorv32
make TOOLCHAIN_PREFIX=/path/to/ECE9433-SoC-Design-Project/third_party/riscv-toolchain/bin/riscv-none-elf- firmware/firmware.hex
```

This creates `firmware/firmware.hex`, which we preload into the behavioral SRAM via `$readmemh` for the PicoRV32 bring-up tests.

## PEU Sanity Test Firmware

We keep a minimal PEU test in `firmware/peu_test/` so the third-party submodule stays untouched. Build it with:

```bash
cd /path/to/ECE9433-SoC-Design-Project/firmware/peu_test
make clean && make
```

This produces `peu_test.hex`, which writes operands to the PEU CSRs, starts the accelerator (stubbed as an add), polls DONE, compares the result to a software reference, and asserts `ebreak` only on success. A mismatch spins forever, so the testbench times out and reports FAIL.

## CPU Heartbeat Simulation (VCS)

Compile and run the minimal SoC top + testbench with VCS:

```bash
cd /path/to/ECE9433-SoC-Design-Project
mkdir -p build
vcs -full64 -kdb -sverilog \
    sim/soc_top_tb.sv rtl/soc_top.sv rtl/interconnect.sv rtl/sram.sv rtl/peu.sv third_party/picorv32/picorv32.v \
    -o build/soc_top_tb
./build/soc_top_tb
```

What to expect:
- The simulator prints the firmware load message and halts when the firmware asserts `trap`. With `peu_test.hex` it reports `Firmware completed after 106 cycles. PASS`. If the firmware spins (any mismatch), the bench times out at 200 000 cycles and prints FAIL.
- Point `HEX_PATH` in `sim/soc_top_tb.sv` to a different hex if you want to run other firmware images; the VCS flow stays the same.

## Synthesis (Design Compiler) — Read RTL & Elaborate

Use the tutorial flow but point to our sources:

```tcl
set_app_var sh_enable_page_mode false
source tcl_scripts/setup.tcl                ;# stdcell + SRAM .db in target/link libs
analyze -define SYNTHESIS -format sverilog {
    ../rtl/soc_top.sv
    ../rtl/interconnect.sv
    ../rtl/sram.sv
    ../rtl/peu.sv
    ../third_party/picorv32/picorv32.v
}
elaborate soc_top
current_design soc_top
```

Notes / pitfalls:
- Define `SYNTHESIS` so sim-only constructs (`$readmemh`, initial blocks) are skipped during DC.
- `rtl/sram.sv` maps to the TSMC16 macro `TS1N16ADFPCLLLVTA512X45M4SWSHOD` for synthesis; the behavioral RAM remains under `ifndef SYNTHESIS` for VCS.
- The SRAM timing lib `N16ADFP_SRAM_tt0p8v0p8v25c_100a.db` is included via `setup.tcl` to avoid flop-based RAM inference.
- Picorv32 emits many signed/unsigned and unreachable warnings in elaboration; they are expected and non-fatal.
