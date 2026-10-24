/*
 * Embedded Operating Systems and Architecture course
 * Licensed under the MIT License. See LICENSE in the repository root.
 *
 * Program start-up code, linked first into every loadable program (see
 * programs/program.ld). It is NOT part of the kernel: each program has
 * its own copy, at address 0 of its ELF file.
 *
 * When the kernel starts a loaded program, everything a C program needs
 * is already in place:
 *   - the loader has copied code and data into the slot, filled BSS with
 *     zeros and relocated every absolute address;
 *   - PSP points at the top of the slot (task_program_create builds the
 *     first stack frame there);
 *   - the task runs unprivileged in thread mode.
 * So _start only has to call main and turn its return into an exit.
 *
 * C equivalent:
 *     void _start(void) { main(); sys_exit(); }
 */

    .syntax unified
    .cpu cortex-m3
    .thumb

    /* .text.start is placed first by programs/program.ld, so _start is
     * always at offset 0 of the code. The ELF entry point names it. */
    .section .text.start,"ax",%progbits

    .global _start
    .type _start, %function
    .thumb_func                 /* bit 0 set: e_entry is a Thumb address */
_start:
    bl main                     /* main(); its int result is ignored */
    /* Returning from main ends the program exactly like sys_exit(): the
     * kernel prints "program <name> exited", saves status 0, wakes the
     * waiters and frees the slot. sys_exit never returns. */
    bl sys_exit
    .size _start, . - _start
