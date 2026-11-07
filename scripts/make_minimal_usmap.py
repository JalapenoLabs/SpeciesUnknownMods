#!/usr/bin/env python3
# Copyright © 2026 Jalapeno Labs
"""Write a minimal .usmap that lets UAssetAPI tools parse a cooked Blueprint's functions.

The game's assets use unversioned properties, so UAssetAPI (and kismet-analyzer, which is built on it) leaves every
export as raw bytes unless it has a mappings file with a schema for the export's class. Function exports carry no
tagged properties, so empty schemas for the UFunction class chain are enough to reach their bytecode. Class and
CDO exports stay raw; reading their property values needs a real .usmap dumped by UE4SS from the running game.

Usage: make_minimal_usmap.py <output.usmap>
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# Class name -> parent class name, root first. Every schema is empty.
_CLASS_CHAIN = {
    "Object": None,
    "Field": "Object",
    "Struct": "Field",
    "Function": "Struct",
    "Class": "Struct",
    "BlueprintGeneratedClass": "Class",
}

_USMAP_MAGIC = 0x30C4
_USMAP_VERSION_INITIAL = 0
_COMPRESSION_NONE = 0
_NO_PARENT = 0xFFFFFFFF


def main() -> None:
    """Build the usmap payload (names, no enums, empty schemas) and write it uncompressed."""
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {Path(sys.argv[0]).name} <output.usmap>")

    names = list(_CLASS_CHAIN)
    payload = struct.pack("<I", len(names))
    for name in names:
        encoded_name = name.encode("ascii")
        payload += struct.pack("<B", len(encoded_name)) + encoded_name

    payload += struct.pack("<I", 0)
    payload += struct.pack("<I", len(_CLASS_CHAIN))
    for name, parent in _CLASS_CHAIN.items():
        parent_index = _NO_PARENT if parent is None else names.index(parent)
        payload += struct.pack("<IIHH", names.index(name), parent_index, 0, 0)

    header = struct.pack(
        "<HBBII",
        _USMAP_MAGIC,
        _USMAP_VERSION_INITIAL,
        _COMPRESSION_NONE,
        len(payload),
        len(payload),
    )
    output_path = Path(sys.argv[1])
    output_path.write_bytes(header + payload)
    print(f"Wrote {output_path} ({len(header) + len(payload)} bytes)")


if __name__ == "__main__":
    main()
