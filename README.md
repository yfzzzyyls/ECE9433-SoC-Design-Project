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

We now use DC NXT W-2024.09-SP5-5. The PDK as delivered lacks tech RC (TLU+) files and an SRAM NDM; topo runs will warn about missing RC per-layer attributes and mark SRAM macros `dont_use`. Per professor, this is OK for now—run a logical (non-topo) compile to get a mapped netlist. Representative topo log snippet (expected):
- `Library analysis succeeded.`
- `Warning: No TLUPlus file identified. (DCT-034)`
- `Error: Layer 'M1' is missing the 'resistance' attribute. (PSYN-100)` … similar for M2–M11/AP
- SRAM cells marked `dont_use` due to missing physical view.

Recommended non-topo flow (fresh session):

```tcl
set_app_var sh_enable_page_mode false
set_app_var alib_library_analysis_path /home/fy2243/ECE9433-SoC-Design-Project/alib
source tcl_scripts/setup.tcl
analyze -define SYNTHESIS -format sverilog {../rtl/soc_top.sv ../rtl/interconnect.sv ../rtl/sram.sv ../rtl/peu.sv ../third_party/picorv32/picorv32.v}
elaborate soc_top
current_design soc_top
source /home/fy2243/ECE9433-SoC-Design-Project/tcl_scripts/soc_top.con
compile_ultra
write -hier -f ddc -output ../mapped/soc_top.ddc
write -hier -f verilog -output ../mapped/soc_top.v
```

Notes / pitfalls:
- Define `SYNTHESIS` so sim-only constructs (`$readmemh`, initial blocks) are skipped during DC.
- `rtl/sram.sv` maps to the TSMC16 macro `TS1N16ADFPCLLLVTA512X45M4SWSHOD` for synthesis; the behavioral RAM remains under `ifndef SYNTHESIS` for VCS.
- The SRAM timing lib `N16ADFP_SRAM_tt0p8v0p8v25c_100a.db` is included via `setup.tcl` to avoid flop-based RAM inference.
- Picorv32 emits many signed/unsigned and unreachable warnings in elaboration; they are expected and non-fatal.
- Topo mode will halt without tech RC and SRAM physical views; stick to non-topo until/unless tech/TLU+ and SRAM NDM are provided.

## Innovus Bring-Up (batch, legacy mode)

Prereqs: mapped netlist at `mapped/soc_top.v`, SDC at `tcl_scripts/soc_top.sdc`, and PDK collateral at `/ip/tsmc/tsmc16adfp/...` as referenced in the Tcl scripts.

Run:
```bash
cd /home/fy2243/ECE9433-SoC-Design-Project
export PATH=/eda/cadence/INNOVUS211/bin:$PATH   # tcsh: set path = (/eda/cadence/INNOVUS211/bin $path)
innovus -no_gui -overwrite -files tcl_scripts/innovus_flow.tcl
```
What happens:
- Uses legacy init with `init_mmmc_file=tcl_scripts/innovus_mmmc_legacy.tcl` so timing is active at `init_design`.
- Reads tech/stdcell/SRAM LEF, mapped netlist, applies SDC, creates a 60% util floorplan, places/fixes the SRAM, runs `timeDesign -prePlace`.
- Checkpoints are written to `pd/innovus/init.enc` and `pd/innovus/init_timed.enc`; timing reports drop into `timingReports/`.

If you want to restore the timed checkpoint in a GUI session:
```bash
cd /home/fy2243/ECE9433-SoC-Design-Project
export PATH=/eda/cadence/INNOVUS211/bin:$PATH
innovus -common_ui
# at the Innovus prompt:
restoreDesign pd/innovus/init_timed.enc
gui_fit
```

## Tech-Aware DRC-Clean Flow (Unified, STARRC + QRC, 0 violations)

This is the single, recommended flow (parasitic-aware synthesis + QRC P&R).

1) Synthesis with STARRC tech
```bash
cd /home/fy2243/ECE9433-SoC-Design-Project
dc_shell -f syn_complete_with_tech.tcl 2>&1 | tee synthesis_complete.log
```
Outputs (in `mapped_with_tech/`): `soc_top.v`, `soc_top.ddc`, `soc_top.sdc`, `area.rpt`, `timing.rpt`, `power.rpt`, `qor.rpt`.

2) Innovus P&R with QRC tech (DRC-priority)
```bash
cd /home/fy2243/ECE9433-SoC-Design-Project
export PATH=/eda/cadence/INNOVUS211/bin:$PATH   # tcsh: set path = (/eda/cadence/INNOVUS211/bin $path)
/eda/cadence/INNOVUS211/bin/innovus -no_gui -overwrite -files tcl_scripts/complete_flow_with_qrc.tcl 2>&1 | tee complete_flow.log
```
What it does:
- Loads QRC tech `/ip/tsmc/tsmc16adfp/tech/RC/N16ADFP_QRC/worst/qrcTechFile` (via `tcl_scripts/innovus_mmmc_legacy_qrc.tcl`)
- Reads tech/stdcell/SRAM LEFs and the synthesized netlist `mapped_with_tech/soc_top.v`
- Floorplan: 30% utilization, 50 µm margins; SRAM placed/fixed; PG connects; process set to 16nm
- Placement → CTS (`ccopt_design -cts`) → DRC-focused routing → metal fill (M1–M6)
- DRC #1: `pd/innovus/drc_complete_1.rpt` (initial markers)
- ECO fix: `ecoRoute -fix_drc`
- DRC #2: `pd/innovus/drc_complete_2.rpt` (“No DRC violations were found”)
- Final checkpoint: `pd/innovus/complete_final.enc`

Notes:
- Keep PATH set to Innovus before running.
- Antenna warnings on the SRAM LEF are expected; QRC still loads and extraction runs.
- Routing is DRC-priority (timing-driven off). Enable timing-driven options later only if you need tighter timing after DRC is clean.
