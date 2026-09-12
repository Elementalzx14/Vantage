"""Generate an original mapper-0 NES test ROM. No commercial ROM data is used.

The background changes from blue to red while controller A is pressed.
This tiny test program and generated ROM are dedicated to the public domain (CC0).
"""
from pathlib import Path
import sys

code = bytearray()
labels = {}
fixups = []


def emit(*values):
    code.extend(values)


def label(name):
    labels[name] = len(code)


def branch(op, name):
    emit(op, 0)
    fixups.append((len(code) - 1, name, True))


def jump(name):
    emit(0x4C, 0, 0)
    fixups.append((len(code) - 2, name, False))


emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A, 0xE8)  # SEI, CLD, stack, X=0
emit(0x8E, 0x00, 0x20, 0x8E, 0x01, 0x20, 0x8E, 0x10, 0x40)
for n in range(2):
    label(f'vblank{n}')
    emit(0x2C, 0x02, 0x20)
    branch(0x10, f'vblank{n}')
emit(0xA9, 0x08, 0x8D, 0x01, 0x20)  # enable background
emit(0xA9, 0x42, 0x8D, 0x00, 0x60)  # battery RAM marker
label('loop')
emit(0xA9, 1, 0x8D, 0x16, 0x40, 0xA9, 0, 0x8D, 0x16, 0x40)
emit(0xAD, 0x16, 0x40, 0x29, 1)
branch(0xF0, 'blue')
emit(0xA9, 0x16)
branch(0xD0, 'paint')
label('blue')
emit(0xA9, 0x21)
label('paint')
emit(0x48)
label('wait')
emit(0x2C, 0x02, 0x20)
branch(0x10, 'wait')
emit(0xA9, 0x3F, 0x8D, 0x06, 0x20, 0xA9, 0, 0x8D, 0x06, 0x20, 0x68, 0x8D, 0x07, 0x20)
emit(0xA9, 0, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
jump('loop')
for offset, name, relative in fixups:
    target = labels[name]
    if relative:
        delta = target - offset - 1
        assert -128 <= delta <= 127
        code[offset] = delta & 255
    else:
        code[offset:offset + 2] = (0x8000 + target).to_bytes(2, 'little')
prg = bytearray(16384)
prg[:len(code)] = code
prg[-6:] = b'\x00\x80' * 3
rom = b'NES\x1a' + bytes([1, 1, 2, 0]) + bytes(8) + prg + bytes(8192)
Path(sys.argv[1]).write_bytes(rom)
