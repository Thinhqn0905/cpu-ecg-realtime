/* Linker Script for CV32E40P Real-Time ECG SoC
   Dual Tightly-Coupled Memory Architecture:
   - 32 KB I-TCM (0x0000_0000 - 0x0000_7FFF)
   - 32 KB D-TCM (0x0001_0000 - 0x0001_7FFF)
*/

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  I_TCM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  D_TCM (rw)  : ORIGIN = 0x00010000, LENGTH = 32K
}

SECTIONS
{
  /* Vectors and Boot Code in I-TCM */
  .vectors :
  {
    . = ALIGN(256);
    KEEP(*(.vectors))
  } > I_TCM

  .text :
  {
    . = ALIGN(4);
    *(.text)
    *(.text.*)
    *(.rodata)
    *(.rodata.*)
    . = ALIGN(4);
    _etext = .;
  } > I_TCM

  /* Initialized data placed in I-TCM at load time, copied to D-TCM */
  .data : AT(_etext)
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    . = ALIGN(4);
    _edata = .;
  } > D_TCM

  /* Zero-initialized BSS in D-TCM */
  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > D_TCM

  /* Stack and Heap in D-TCM */
  .heap :
  {
    . = ALIGN(4);
    _heap_start = .;
    . = . + 0x1000; /* 4 KB Heap */
    _heap_end = .;
  } > D_TCM

  .stack :
  {
    . = ALIGN(16);
    . = . + 0x1000; /* 4 KB Stack */
    _stack_top = .;
  } > D_TCM
}
