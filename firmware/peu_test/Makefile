RISCV_PREFIX ?= /home/zl6115/SoC/Project_intergrated/ECE9433-SoC-Design-Project/third_party/riscv-toolchain/bin/riscv-none-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
CFLAGS  := -Os -march=rv32imc -mabi=ilp32 -ffreestanding -nostdlib
LDFLAGS := -T link.ld -nostartfiles -Wl,--build-id=none,--strip-debug

all: peu_test.hex

peu_test.elf: start.S peu_test.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S peu_test.c

peu_test.bin: peu_test.elf
	$(OBJCOPY) -O binary $< $@
	chmod -x $@

peu_test.hex: peu_test.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 peu_test.elf $@

clean:
	rm -f peu_test.elf peu_test.bin peu_test.hex

.PHONY: all clean
