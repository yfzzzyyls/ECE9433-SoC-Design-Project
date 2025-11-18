RISCV_PREFIX ?= /home/fy2243/ECE9433-SoC-Design-Project/third_party/riscv-toolchain/bin/riscv-none-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
CFLAGS  := -Os -march=rv32imc -mabi=ilp32 -ffreestanding -nostdlib
LDFLAGS := -T link.ld -nostartfiles -Wl,--build-id=none,--strip-debug

all: peu_test.hex

peu_test.elf: peu_test.c start.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ peu_test.c start.S

peu_test.bin: peu_test.elf
	$(OBJCOPY) -O binary $< $@
	chmod -x $@

peu_test.hex: peu_test.bin
	python3 ../../third_party/picorv32/firmware/makehex.py $< 32768 > $@

clean:
	rm -f peu_test.elf peu_test.bin peu_test.hex

.PHONY: all clean
