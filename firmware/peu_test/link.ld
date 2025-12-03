ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 2K
}

SECTIONS {
    .text : {
        *(.init)
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > RAM

    .data : {
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
    } > RAM

    .bss : {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
    } > RAM

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
