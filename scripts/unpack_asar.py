#!/usr/bin/env python3
"""
unpack_asar.py - Standalone, zero-dependency Electron ASAR extractor.
Extracts files from an Electron .asar archive without needing Node/npm.
"""

import sys
import os
import struct
import json

def extract_asar(asar_path, dest_dir):
    if not os.path.isfile(asar_path):
        print(f"[ERROR] ASAR file not found: {asar_path}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(dest_dir, exist_ok=True)

    with open(asar_path, 'rb') as f:
        # ASAR header format:
        # 4 bytes: uint32 (size 4)
        # 4 bytes: uint32 (header size + 8)
        # 4 bytes: uint32 (header size + 4)
        # 4 bytes: uint32 (header json string length)
        # json string
        magic = f.read(4)
        f.seek(12)
        header_len = struct.unpack('<I', f.read(4))[0]
        header_raw = f.read(header_len).decode('utf-8')
        header = json.loads(header_raw)
        payload_base = 16 + header_len

        def walk(node, current_dir):
            os.makedirs(current_dir, exist_ok=True)
            files = node.get('files', {})
            for name, info in files.items():
                target_path = os.path.join(current_dir, name)
                if 'files' in info:
                    walk(info, target_path)
                elif 'offset' in info and 'size' in info:
                    offset = payload_base + int(info['offset'])
                    size = int(info['size'])
                    f.seek(offset)
                    data = f.read(size)
                    with open(target_path, 'wb') as out_f:
                        out_f.write(data)

        walk(header, dest_dir)
    print(f"[OK] Successfully extracted {asar_path} -> {dest_dir}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 unpack_asar.py <path-to-app.asar> <destination-dir>")
        sys.exit(1)
    extract_asar(sys.argv[1], sys.argv[2])
