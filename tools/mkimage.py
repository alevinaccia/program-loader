"""
    Requisite 6.3
    This tool packs all the given compiled programs into a 
    custom img1 file. It checks if the given programs are valid elfs 
    and packs the image following the provided structure.

    It can be used as follow:
    python3 mkimage.py image build/fs.img [hello=build/programs/hello.elf...]

    File Structure (IMG1)
    0x0 -> Header of 20 bytes
        0..3   Magic -> 0x31474d49
        4..7   Version -> 1
        8..11  Image_Size
        12..15 Count -> Number of programs (MAX 32)
        16..19 Directory Offset [in this case is fixed at 20]

    0x14 -> Directory (Count * 24) Where each entry has 24 bytes:
        0..15  Name and a NUL byte
        15..19 Offset (where the program starts)
        20..23 Size of the program file (at least 40 bytes)

    0x14 + 24 * Count -> Contents
"""

import argparse
import sys
import re
import struct
from typing import Optional
from pathlib import Path

#HEADER
IMAGE_MAGIC = 0x31474d49
IMAGE_VERSION = 1
HEADER_SIZE = 20

#DIRECTORY
NAME_FIELD = 16
ENTRY_SIZE = 24

# CONSTRAINTS
MAX_PROGRAMS = 32
MAX_IMAGE_SIZE = 0x00200000  #max 2MiB
MIN_PROGRAM_SIZE = 40           # programs must be at least 40 bytes
NAME_RE = re.compile(r"[A-Za-z0-9_-]{1,15}") # at most 15 character with no special characters

ELF_HEADER = b"\x7fELF"
def check_elf(filename : str, data : bytes):
    if data[:4] != ELF_HEADER:
        return True
    return False

def parse_programs(parser : argparse.ArgumentParser , program_specs : list[str]):
    if program_specs.__len__() < 1:
        parser.error("No program was given")
    if program_specs.__len__() > MAX_PROGRAMS:
        parser.error(f"Too many programs, maximum is {MAX_PROGRAMS}, received {program_specs.__len__()}")
    programs : list[tuple[str, bytes]] = []
    seen = set[str]()

    for spec in program_specs:
        name, sep, filename = spec.partition("=")
        if not sep or not filename:
            parser.error(f"expected NAME=program.elf, got {spec!r}")
        if not NAME_RE.fullmatch(name):
            parser.error(f"Invalid program name {name!r}: only numbers, letters _ and -")
        if filename in seen:
            parser.error(f"Duplicate program name {name!r}")
        seen.add(name)

        try:
            data = Path(f'{filename}').read_bytes()
        except OSError as error:
            parser.error(f"Cannot read {filename}: {error.strerror}")
        if data.__len__() < MIN_PROGRAM_SIZE:
            parser.error(f"Programs must be at least 40 bytes, {filename} is {data.__len__()}")

        problem = check_elf(filename, data)
        if problem:
            parser.error(f"{filename} is not a valid elf file");

        programs.append((name, data));  
    return programs

def pack_image(parser: argparse.ArgumentParser, programs : list[tuple[str, bytes]]):
    contents_start = HEADER_SIZE + len(programs) * ENTRY_SIZE
    directory = bytearray()
    contents = bytearray()

    for name, data in programs:
        contents += b"\0" * (-(contents_start + len(contents)) % 4) # round to multiple of 4?
        offset = contents_start + len(contents) #the current program starts at start + current length
        directory += name.encode("ascii").ljust(NAME_FIELD)
        directory += struct.pack("<II", offset, len(data)) 
        contents += data
    
    image_size = contents_start + len(contents)

    # "<5I" means Little Endian (<), 5 values, Unsigned integers 32bits (I)
    header = struct.pack("<5I", IMAGE_MAGIC, IMAGE_VERSION, image_size, len(programs), HEADER_SIZE)
    image = header + directory + contents

    if (len(image) > MAX_IMAGE_SIZE):
        parser.error(f"Image exceeds the size limit")

    return image

def main(argv: Optional[list[str]] = None):
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    image = commands.add_parser("image")
    image.add_argument("output", type=Path)
    image.add_argument("programs", nargs="*", metavar="NAME=PROGRAM.elf")
    args = parser.parse_args(argv)

    programs = parse_programs(parser ,args.programs)
    image = pack_image(parser, programs)

    try:
        #create the directory that the user has given as input (if it doesnt exist)
        args.output.parent.mkdir(parents = True, exist_ok=True)
        #put those bytes in a file at the specified location
        args.output.write_bytes(image)

    except OSError as error:
        parser.error(f"cannot write {args.output}: {error.strerror}")
    print(f"IMG1: {args.output} ({len(image)}bytes, {len(programs)} programs)")

if __name__ == "__main__":
    sys.exit(main())