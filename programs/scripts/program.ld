

ENTRY(_start)
PROGRAM_MAX_SIZE = 3072; /* a program can be at most 3kb */
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

  ASSERT(_runtime_end <= _code_start, "runtime does not fit below code offset")
  ASSERT(_program_end < PROGRAM_MAX_SIZE, "Program is larger than 4kb")
}
