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
