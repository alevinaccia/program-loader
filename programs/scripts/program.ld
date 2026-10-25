/* Linker script used for the programs
 * each program must be below 3kb. 
 * The structure is: 
 *    0x0 Begin
 *        Runtime code (stubs)
 *    0x280  main
 *           text
 *           read only data
 *
 *           Some padding is added for the W^X constraint (512)
 *           data
 *           bss
 *    0xc00  program end.
 *    0x1000 stack pointer
 *
 * Since thise programs will be loaded into memory at runtime,
 * we need to put the main at a fixed location so that the os can start it. 
 * The linker makes sure that the runtime is less than 280byes.
 * */

ENTRY(_start)
PROGRAM_MAX_SIZE = 3072; /* a program can be at most 3kb */
STACK_SIZE = 1024;
PROGRAM_CODE_OFFSET = 0x280; /* where main is */

WX_ALIGN = 512;

PHDRS
{
    text PT_LOAD FLAGS(5); /* text read but not write */
    data PT_LOAD FLAGS(6); /* data read and write */
}

SECTIONS 
{
  . = 0;

  .text :
  {
    KEEP(*(.text.start))
    */runtime/*.o(.text .text.*)            /* stubs, printf, format */
    _runtime_end = .;

    . = PROGRAM_CODE_OFFSET;

    _code_start = .;
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
    _code_end = .;
  } : text

  . = ALIGN(WX_ALIGN);

  .data :
  {
    _data_start = .;
    *(.data .data.*)
    . = ALIGN(4);
    _data_end = .;
  } : data

  .bss :
  {
    *(.bss .bss.* COMMON)
    . = ALIGN(4);
    _program_end = .;
  } : data

  .stack (NOLOAD) :
  {
    . = PROGRAM_MAX_SIZE;
    _estack = . + STACK_SIZE;
  }

  ASSERT(_runtime_end <= _code_start, "runtime does not fit below code offset")
  ASSERT(_program_end <= PROGRAM_MAX_SIZE, "Program is larger than 4kb")
  ASSERT(_program_end <= _estack - STACK_SIZE, "Stack is overflowing")

}
