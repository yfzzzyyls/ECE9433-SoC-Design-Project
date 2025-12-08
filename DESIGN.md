MVP Principle: the entire SoC effort remains scoped to the smallest feature set needed to reach a DRC/LVS-clean tapeout—single PicoRV32 core, minimal interconnect, CORDIC accelerator that passes a simple hand-written firmware test—and no additional complexity or exhaustive verification beyond that bar.

## Progress Log

### Step 1 — Cross-Compiler Bring-Up (Completed)
- Installed the xPack `riscv-none-elf` toolchain under `third_party/riscv-toolchain/`.
- Documented the download/extraction commands and PATH export in `README.md`.
- Verified `riscv-none-elf-gcc` is available on the command line, unblocking firmware builds for PicoRV32 bring-up.

### Step 2 — Reference Firmware Build (Completed)
- Invoked `make firmware/firmware.hex` inside `third_party/picorv32` (overriding `TOOLCHAIN_PREFIX`) to generate the baseline hello firmware.
- Captured the exact build command in `README.md` so collaborators can reproduce the `.hex` image.
- Output `firmware/firmware.hex` is ready to be preloaded via `$readmemh` during CPU bring-up.

### Step 3 — CPU Heartbeat Simulation (Completed)
- Compiled `rtl/soc_top.sv` with `sim/soc_top_tb.sv` and `third_party/picorv32/picorv32.v` under VCS.
- Ran the simulator loading `firmware/firmware.hex`; firmware hit `trap` after 24 cycles with no timeout, confirming the minimal SoC (CPU + SRAM preload) is functional.

### SRAM Macro Note (In Progress)
- For synthesis we now map `rtl/sram.sv` to the TSMC16 `TS1N16ADFPCLLLVTA512X45M4SWSHOD` (512 words × 45 bits ≈ 2 KB usable at 32-bit). The behavioral array and `$readmemh` remain for simulation under `ifndef SYNTHESIS`.
- DC setup includes the SRAM NLDM/lib so the macro links instead of exploding into flip-flops; ensure firmware fits within the ~2 KB macro footprint for synthesized builds.

### DC Synthesis Attempts (Topo vs Non-Topo)
- Topo runs on DC NXT W-2024.09-SP5-5: library analysis succeeds, but `compile_ultra` halts with PSYN-100/101 errors (M1–M11/AP missing resistance/capacitance) because no TLU+/tech RC files are available. SRAM macros are marked `dont_use` in topo due to missing SRAM physical views (no SRAM NDM).
- Older DC (U-2022.12) was crashing during library analysis; the newer build cleared that crash, but topo still blocks without RC/physical data.
- If topo is required, we need to supply TLU+/tech files and an SRAM physical view so the macro is usable. As a workaround, a non-topo (logical-only) `compile_ultra` can be run, which does not require RC data or SRAM NDM.
- Checked the PDK: stdcell NDM is present; SRAM has LEF/GDS but no NDM, and no TLU+/tech RC files were found. Professor confirmed tech files aren’t provided and not required for our flow. Conclusion: proceed with a non-topo logical compile to get a mapped netlist; P&R will use LEF/GDS for physical implementation.

### X11 GUI Access (Completed)
- Verified X forwarding via XQuartz on macOS (`ssh -Y`, DISPLAY=localhost:…), allowing DC GUI to launch/render correctly after clearing stale DLIB state.

## Next Phase: Design Flow and CORDIC Integration
- Backend prep: set up synthesis scripts (DC) and constraints (clocks, reset) for the current RTL; plan memory macro replacement for the behavioral SRAM using the TSMC 16nm PDK.
- Interface stability: keep the existing MMIO map (SRAM at low addresses, PEU at 0x1000_0000 with SRC0/SRC1/CTRL/STATUS/RESULT) while swapping the PEU stub for the real CORDIC datapath.
- Macro integration: swap the behavioral SRAM for the appropriate SRAM macro/compiler output with identical interface signals before P&R.
- Tapeout flow: after RTL with real PEU is in place, rerun synthesis and proceed through P&R, then DRC/LVS signoff targeting the MVP feature set.

## Progress

### Dec 5, 2025
- Switched to DC NXT W-2024.09-SP5-5; topo runs still blocked by missing TLU+/tech RC files and no SRAM NDM. Professor confirmed tech RC files aren't provided; SRAM physical views exist as LEF/GDS only.
- Ran a successful non-topo `compile_ultra` (DC 2022): synthesis completed with warnings:
  - TIM-134: high-fanout net `u_cpu/genblk1.pcpi_mul/clk` (~2000 loads).
  - TIM-164: SRAM timing trip points differ from stdcell lib.
  - PWR-428: unannotated black-box outputs (macro activity not annotated).
- Outputs: mapped netlist/DDC were written; timing/area reports can be generated from the current session. Non-topo flow is the recommended path until RC/NDM for SRAM are available.
- Hold report still shows ~–0.16 ns on SRAM D/A/BWEB pins (zero-RC, non-topo); agreed to defer hold fixing to P&R where real RC/CTS can pad these paths.
- Standardized mapped deliverables to a single set: `mapped/soc_top.v`, `mapped/soc_top.ddc`, and reports `mapped/timing.rpt`, `mapped/area.rpt`, `mapped/constraints_violators.rpt`; removed older temp variants from `mapped/`.

#### Innovus P&R Setup (Completed)
- **Fixed Innovus v21.18 initialization errors** that were blocking design import:
  1. **Init sequence error (IMPIMEX-12):** Old-style `init_design` variables deprecated. Updated `tcl_scripts/innovus_init.tcl` to new v21.x syntax: `read_mmmc` → `read_physical -lefs` → `read_netlist` → `init_design`.
  2. **MMMC delay corner syntax:** `-library_set` option replaced with `-timing_condition`. Updated `tcl_scripts/innovus_mmmc.tcl` to use `create_timing_condition` before `create_delay_corner`.
  3. **Invalid command:** Removed `set_top_module` (netlist reader sets top cell automatically).
- **Successful design import** into Innovus v21.18:
  - ✅ Loaded timing libraries: N16ADFP_StdCell + SRAM (1490 cells from NLDM .lib files)
  - ✅ Loaded physical libraries: Tech LEF + StdCell LEF + SRAM LEF
  - ✅ Read netlist: `mapped/soc_top.v` (11,533 standard cells + 1 SRAM macro TS1N16ADFPCLLLVTA512X45M4SWSHOD)
  - ✅ Applied constraints: `tcl_scripts/soc_top.sdc` (100 MHz clock, I/O delays)
  - ✅ Created floorplan: 60% utilization, SRAM macro placed at (50, 50) R0 orientation
  - ✅ Saved checkpoints: `pd/innovus/init.enc` (initial) and `pd/innovus/init_timed.enc` (with timing)
- **Warnings resolved (benign):**
  - TECHLIB-302: TAP/FILL cells have no function (expected—physical-only cells)
  - IMPLF-200/201: Missing antenna data in SRAM LEF (can ignore unless doing antenna rule checking)
  - IMPOPT-801: Genus not in PATH (not needed for Innovus-only flow)
- **Ready for P&R:** Design is now imported, timed, and floorplanned. Next steps: placement → CTS → routing → signoff.
- **Run command:** `cd /home/fy2243/ECE9433-SoC-Design-Project && innovus -common_ui -overwrite -files tcl_scripts/innovus_flow.tcl`
- **Restore checkpoint:** `innovus -common_ui` then `restoreDesign pd/innovus/init_timed.enc`

### Dec 6, 2025 — Notes from Piazza threads
- CTS cell lists: you can let CTS pick defaults, but if you want to constrain, use clock buffers/inverters with prefixes like `CKB/CKN`, drive strength in the number (1–16), and optional LVT suffix (P90 is just poly pitch). Cells are visible in both stdcell .lib and .lef.
- Power planning: use M11 as top metal for rings/straps; AP12 is RDL and not needed here. AP layers are different metal and usually reserved for bump/RDL.
- Voltus rail analysis: the PDK likely lacks PGV/powergrid/extraction tech files, so early rail analysis may emit missing-power-pin or missing-PGV warnings; may be unsupported in this class.
- Scan DEF: not required unless doing DFT. Tool should generate what it needs for this project.
- Gate-level sim reminder: use the mapped netlist `.v` plus the stdcell model file (e.g., `N16ADFP_StdCell.v`) with the same testbench if it doesn’t rely on internal names.

### Dec 7, 2025 — Innovus bring-up fixed
- Problem: Timing wasn’t initializing in Innovus; runs were in physical-only mode (IMPSYT-7328) and `create_delay_corner` complained about missing library_set. `floorPlan` only exists in legacy batch mode, and `init_mmmc_file` was coming in as `{}`.
- Fixes applied:
  - Switched to legacy init mode (`innovus -no_gui -overwrite`) with `init_mmmc_file` pointing to `tcl_scripts/innovus_mmmc_legacy.tcl` (normalized path so it’s not empty).
  - Legacy MMMC uses `create_library_set` + `create_delay_corner -library_set ...` and sets the analysis view before init_design, so timing is live at init.
  - Floorplan still uses `floorPlan -site core -r 1.0 0.60 20 20 20 20`; SRAM placed/fixed at (50,50); checkpoints saved.
- Current status: Full bring-up and timing run succeed in batch mode.
  - Command: `cd /home/fy2243/ECE9433-SoC-Design-Project && export PATH=/eda/cadence/INNOVUS211/bin:$PATH && innovus -no_gui -overwrite -files tcl_scripts/innovus_flow.tcl`
  - MMMC: `view_typ` active; stdcell + SRAM NLDM loaded.
  - `timeDesign -prePlace`: WNS ~7.666 ns, TNS 0, 0 violating paths (pre-route, default RC with LEF sheet/via defaults).
  - Checkpoints: `pd/innovus/init.enc` and `pd/innovus/init_timed.enc` updated.
- Remaining warnings: antenna data missing on SRAM LEF (IMPLF-200/201), tap/fill cells without function (TECHLIB-302), via/sheet-R defaults (IMPEXT-2766/2773) because no TLU+; expected/benign for this flow.
