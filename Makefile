# Embedded Operating Systems and Architecture course
# Licensed under the MIT License. See LICENSE in the repository root.
#
# Contact: Stefano Di Carlo <stefano.dicarlo@polito.it>

# ARM bare-metal cross-compiler: runs on the host, emits Cortex-M code.
CC := arm-none-eabi-gcc

# The time slice of the round-robin scheduler, in ticks (one tick =
# 10 ms). Change it from the command line: `make QUANTUM=2 run`.
QUANTUM ?= 5

# All generated files go under build/; `make clean` just deletes it.
BUILD_DIR := build
# Final linked image. .axf is ARM's name for an ELF carrying debug info.
BIN := $(BUILD_DIR)/scratch-os.axf
IMAGE := $(BUILD_DIR)/fs.img
IMAGE_ADDR := 0x00200000
IMAGE_TOOL ?= tools/mkimage.py
PROGRAM_DIR ?= programs

# The folders that hold our source files, one folder per OS layer.
SRC_DIRS := boot kernel drivers lib src
# Find every .c file (C code) and every .s file (assembly) in those
# folders. `wildcard` is make's way of listing files that match a pattern,
# so a new file is built automatically, with no change to this Makefile.
SOURCES := $(foreach d,$(SRC_DIRS),$(wildcard $(d)/*.c) $(wildcard $(d)/*.s))
# Map each foo.c or foo.s to its build/foo.o object file. The object
# keeps the folder name, e.g. kernel/irq.s becomes build/kernel/irq.o.
# Two nested patsubst calls: the inner one rewrites ".s" sources, the
# outer one rewrites ".c" sources (a word that does not match is left
# alone, so each source is changed by the one that applies to it).
OBJECTS := $(patsubst %.c,$(BUILD_DIR)/%.o,$(patsubst %.s,$(BUILD_DIR)/%.o,$(SOURCES)))

# -mthumb / -mcpu: target the Cortex-M3's Thumb instruction set.
# -nostartfiles: no default C startup code - boot/startup.s is ours.
# -ffreestanding: no hosted environment - no full standard library, no
#  special meaning for main. Together with -nostdlib below, this makes
#  "no C library" true of the image.
# -std=gnu17: C17 plus GNU extensions (used by the inline-asm blocks).
CFLAGS := -mthumb -mcpu=cortex-m3 -nostartfiles -ffreestanding -std=gnu17
# -Iinclude: look for #include "..." headers in the include/ folder,
# so every file can write #include "cmsdk.h" whatever its own folder.
CFLAGS += -Iinclude
# -I.: also look in the project folder itself (the one holding this
# Makefile). Every other header is then written with its folder, e.g.
# #include "drivers/uart.h", the same from whatever file includes it.
CFLAGS += -I.
# -fno-builtin: GCC normally treats names like printf as the C library
# function it knows. There is no C library here (-nostdlib): our own
# printf in lib/printf.c is a plain function like any other.
CFLAGS += -fno-builtin
# Enable the standard and extra warning sets.
CFLAGS += -Wall -Wextra
# -O0 + full debug info: keep the generated code close to the source so
# it can be stepped through instruction by instruction in class.
CFLAGS += -O0 -g3
# Not -Werror: this code is kept across course years, and a new compiler
# warning should not stop the build.

# Pass the quantum to the C code: -DQUANTUM=5 defines QUANTUM as 5,
# as if kernel/task.h had `#define QUANTUM 5`.
CFLAGS += -DQUANTUM=$(QUANTUM)

# Use our linker script instead of the toolchain's default.
LDFLAGS := -T scripts/mps2_m3.ld
# Also write a map file: it shows which symbol landed at which address.
LDFLAGS += -Xlinker -Map=$(BUILD_DIR)/output.map
# -nostdlib: do not link a C library or its startup code.
# -lgcc: still link libgcc, the small compiler helper library (for
# example software integer division, which the compiler may use alone).
LDFLAGS += -nostdlib -lgcc

# The command line that starts QEMU: the MPS2-AN385 board, no monitor
# console, no window, UART0 connected to this terminal, our image as
# the program. There is no semihosting: all output goes through the UART.
# QEMU_IMAGE is the IMG1 file QEMU's generic loader puts at 0x00200000
# (`make demo` replaces it with the test-kit image).
QEMU_IMAGE = $(IMAGE)
QEMU = qemu-system-arm -machine mps2-an385 -monitor null -nographic -serial stdio -kernel $(BIN) \
       -device loader,file=$(QEMU_IMAGE),addr=$(IMAGE_ADDR),force-raw=on

# These targets are command names, not files on disk.
.PHONY: all clean image run debug run-trace test check programs test-image demo

# Default goal: build the image.
all: $(BIN)

# Compile one .c file to a .o file, creating its build folder first.
$(BUILD_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble one .s file (hand-written assembly) to a .o file. We still
# call $(CC): GCC hands a ".s" file straight to the assembler, and the
# same CPU flags make the assembly match what the C files use.
$(BUILD_DIR)/%.o: %.s
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# Link every object file into the final image. The linker script is a
# prerequisite too, so editing it makes make link again.
$(BIN): $(OBJECTS) scripts/mps2_m3.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJECTS) -o $(BIN)

# ---------------------------------------------------------------------
# Loadable programs (assignment R1). Each program is built separately
# from the kernel: its own start-up code (programs/crt0.s), its own copy
# of the system-call stubs, printf and formatting code (compiled again
# from lib/ with program flags), and libgcc. It is linked at address 0
# with --emit-relocs by programs/program.ld, into one ELF per program.
# ---------------------------------------------------------------------
PROG_BUILD := $(BUILD_DIR)/programs
RUNTIME_DIR := $(PROG_BUILD)/runtime

# Same CPU and freestanding flags as the kernel. -Os: a program has only
# 3 KiB for code, data and BSS. -g: `add-symbol-file` in GDB (README).
PROG_CFLAGS := -mthumb -mcpu=cortex-m3 -ffreestanding -fno-builtin -std=gnu17
PROG_CFLAGS += -I. -Wall -Wextra -Os -g
# --emit-relocs keeps the relocation records the kernel needs. -n turns
# off page alignment of the segments in the file (no 4 KiB of padding).
PROG_LDFLAGS := -nostdlib -nostartfiles -T programs/scripts/program.ld
PROG_LDFLAGS += -Wl,--emit-relocs -Wl,-n -Wl,--build-id=none

# The program runtime. The linker script places these objects (any
# */runtime/*.o) first; main of every program follows at offset 0x280.
RUNTIME_OBJS := $(RUNTIME_DIR)/crt0.o $(RUNTIME_DIR)/syscalls.o \
                $(RUNTIME_DIR)/printf.o $(RUNTIME_DIR)/format.o

# Every programs/NAME.c is a program called NAME in the image.
PROGRAMS := $(sort $(basename $(notdir $(wildcard $(PROGRAM_DIR)/*.c))))
PROGRAM_OBJS := $(PROGRAMS:%=$(PROG_BUILD)/%.o)
PROGRAM_ELFS := $(PROGRAMS:%=$(PROG_BUILD)/%.elf)

# Static pattern rules ("targets: pattern: prerequisites") apply only to
# the targets they list, so the kernel's generic build/%.o rules never
# compile a program file with kernel flags.
$(RUNTIME_DIR)/crt0.o: programs/crt0.s
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@
$(RUNTIME_DIR)/syscalls.o: lib/syscalls.s
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@
$(RUNTIME_DIR)/printf.o $(RUNTIME_DIR)/format.o: $(RUNTIME_DIR)/%.o: lib/%.c
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@

$(PROGRAM_OBJS): $(PROG_BUILD)/%.o: $(PROGRAM_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@

# Link one program: runtime first, then the program, then libgcc. Also
# used for the test-kit programs below.
PROG_LINK = $(CC) $(PROG_CFLAGS) $(PROG_LDFLAGS) -Wl,-Map=$(@:.elf=.map) $(RUNTIME_OBJS) $< -lgcc -o $@

$(PROGRAM_ELFS): %.elf: %.o $(RUNTIME_OBJS) programs/scripts/program.ld
	$(PROG_LINK)

programs: $(PROGRAM_ELFS)

# The image: every program, in name order, packed unchanged with the
# exact "image" command and explicit NAME=PROGRAM.elf arguments. The
# programs/ folder is a prerequisite too: adding or deleting a file there
# changes its time stamp, so the image is rebuilt with the new list.
$(IMAGE): $(PROGRAM_ELFS) $(IMAGE_TOOL) $(PROGRAM_DIR)
	@mkdir -p $(dir $@)
	python3 $(IMAGE_TOOL) image $@ $(foreach p,$(PROGRAMS),$(p)=$(PROG_BUILD)/$(p).elf)

image: $(BIN) $(IMAGE)

# ---------------------------------------------------------------------
# The published test kit (big suite). Its program sources are built with
# the same runtime and rules as ours; its generator adds the malformed
# ELF files and packs everything into build/test-kit/big/fs.img.
# ---------------------------------------------------------------------
TEST_KIT ?= ../test-kit
TK_BUILD := $(BUILD_DIR)/test-kit
TK_PROGS := $(TK_BUILD)/programs
TK_IMAGE := $(TK_BUILD)/big/fs.img
TK_SMALL := $(basename $(notdir $(wildcard $(TEST_KIT)/small/programs/*.c)))
TK_BIG := $(basename $(notdir $(wildcard $(TEST_KIT)/big/programs/*.c)))
TK_ELFS := $(TK_SMALL:%=$(TK_PROGS)/%.elf) $(TK_BIG:%=$(TK_PROGS)/%.elf)

$(TK_SMALL:%=$(TK_PROGS)/%.o): $(TK_PROGS)/%.o: $(TEST_KIT)/small/programs/%.c
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@
$(TK_BIG:%=$(TK_PROGS)/%.o): $(TK_PROGS)/%.o: $(TEST_KIT)/big/programs/%.c
	@mkdir -p $(dir $@)
	$(CC) $(PROG_CFLAGS) -c $< -o $@
$(TK_ELFS): %.elf: %.o $(RUNTIME_OBJS) programs/program.ld
	$(PROG_LINK)

# The image names the suite sends to the shell (test-kit/README.md).
# print_plain must come first: the generator derives the malformed
# files from it.
$(TK_IMAGE): $(TK_ELFS)
	python3 $(TEST_KIT)/big/generate_fixtures.py --output-dir $(TK_BUILD)/big/files --image $@ \
	  print_plain=$(TK_PROGS)/print_plain.elf \
	  global_state=$(TK_PROGS)/globals_bss_const.elf \
	  thumb_ptr=$(TK_PROGS)/thumb_function_pointer.elf \
	  nonzero_slot=$(TK_PROGS)/nonzero_slot_relocation.elf \
	  normal_return=$(TK_PROGS)/normal_return.elf \
	  explicit_exit=$(TK_PROGS)/explicit_exit.elf \
	  kernel_store=$(TK_PROGS)/kernel_store.elf \
	  wx_write_code=$(TK_PROGS)/wx_write_code.elf \
	  wx_exec_data=$(TK_PROGS)/wx_exec_data.elf

test-image: $(TK_IMAGE)

# Build, load the image at its fixed FLASH address, then run in QEMU.
run: $(BIN) $(IMAGE)
	$(QEMU)

# Same as `run`, but paused for a debugger:
#   -S             - freeze the emulated CPU at reset
#   -gdb tcp::1234 - open a GDB server on TCP port 1234 and wait there
# From a second terminal, connect with:
#   arm-none-eabi-gdb build/scratch-os.axf   (on Linux: gdb-multiarch)
# (for a demo build, e.g. DEMO=rogue: build/demo-rogue/scratch-os.axf;
#  for QUANTUM=2: build/quantum-2/scratch-os.axf)
# and inside gdb:
#   target remote :1234
debug: $(BIN) $(IMAGE)
	$(QEMU) -S -gdb tcp::1234

# Same as `run`, plus `-d unimp`: QEMU prints a message whenever the
# program touches a register or device that QEMU does not implement.
run-trace: $(BIN) $(IMAGE)
	$(QEMU) -d unimp

# Run the big suite of the published test kit (14 tests, a fresh QEMU
# each) against build/scratch-os.axf and the test-kit image.
test: $(BIN) $(TK_IMAGE)
	python3 $(TEST_KIT)/run_tests.py --suite big --kernel $(BIN) --image $(TK_IMAGE)

# Our own tests, beyond the published suite: host-side tests of the
# image tool, then QEMU tests of the shell, system calls, full slots,
# slot-1 data relocation, broken images, hand-made ELF defects, and
# random damage to ELF headers and tables (tests/README.md).
check: $(BIN) $(IMAGE)
	python3 tests/test_mkimage.py
	python3 tests/private_tests.py $(BIN) $(IMAGE)
	python3 tests/elf_cases.py $(BIN) $(PROG_BUILD)/reloc_demo.elf
	python3 tests/elf_mutations.py $(BIN) $(PROG_BUILD)/print_plain.elf 3

# The demo: the shell with the test-kit image, which also holds the
# malformed files (bad_magic, bad_rel_type, truncated_elf, ...).
demo: QEMU_IMAGE = $(TK_IMAGE)
demo: $(BIN) $(TK_IMAGE)
	$(QEMU)

# Remove every generated file: kernel, programs, images, test-kit build.
clean:
	rm -rf build
