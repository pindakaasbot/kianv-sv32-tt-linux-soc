/* Linker script for KianV SV32 test firmware                */
/* CRT0 runs from FLASH, then copies all code+data to BRAM.  */
/* After init, everything runs from BRAM (PSRAM), freeing    */
/* the shared SPI bus for the SPI master test.                */

MEMORY {
  FLASH      (rx)  : ORIGIN = 0x020000000, LENGTH = 0x10000000
  BRAM       (rwx) : ORIGIN = 0x080000000 + (8*1024*1024 - (32*1024)), LENGTH = 0x00008000
}

__stacktop = ORIGIN(BRAM) + LENGTH(BRAM);

SECTIONS {

    /* CRT0 stays in flash — it's the first code executed at boot */
    .misc : {
        . = ALIGN(4);
        crt0.o(.text)
        . = ALIGN(4);
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.init_array)
        *(.gcc_except_table*)
        . = ALIGN(4);
        _etext = .;
        _sidata = _etext;
    } >FLASH

    /* All other code, rodata, and data go to BRAM (copied from flash by crt0) */
    .data : AT ( _sidata ) {
        . = ALIGN(4);
        _sdata = .;
        _ram_start = .;

        *(.text)
        *(.text*)
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);

        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > BRAM

    /* Uninitialized data section */
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >BRAM

    .heap : {
        . = ALIGN(4);
        _heap_start = .;
        _end = .;
    } >BRAM
}
