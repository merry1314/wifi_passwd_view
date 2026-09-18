#!/usr/bin/env python3
"""
Generate .def files from Windows DLL export tables,
then use lld-link to create .lib import libraries.
This allows building Rust MSVC targets without the Windows SDK.
"""
import struct
import sys
import os
import subprocess

def rva_to_offset(rva, sections):
    """Convert an RVA to a file offset using section headers."""
    for s in sections:
        if s['VirtualAddress'] <= rva < s['VirtualAddress'] + s['VirtualSize']:
            return rva - s['VirtualAddress'] + s['PointerToRawData']
    return None

def read_pe_exports(filepath):
    """Parse PE export table and return list of exported function names."""
    with open(filepath, 'rb') as f:
        data = f.read()

    # DOS header: e_lfanew at offset 0x3C (4 bytes)
    if len(data) < 0x40:
        return []
    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]

    # PE signature
    if data[e_lfanew:e_lfanew+4] != b'PE\x00\x00':
        return []

    # COFF header (20 bytes)
    coff_off = e_lfanew + 4
    machine, num_sections, _, _, _, opt_hdr_size, _ = struct.unpack_from('<HHIIIHH', data, coff_off)

    # Optional header
    opt_off = coff_off + 20
    magic = struct.unpack_from('<H', data, opt_off)[0]
    is_pe32_plus = (magic == 0x20B)

    # Data directories start at different offsets for PE32 vs PE32+
    if is_pe32_plus:
        # PE32+: optional header is 240 bytes, data dirs at offset 112
        dd_off = opt_off + 112
    else:
        # PE32: optional header is 96 bytes, data dirs at offset 96
        dd_off = opt_off + 96

    # Export table is the first data directory entry (RVA + Size)
    export_rva, export_size = struct.unpack_from('<II', data, dd_off)
    if export_rva == 0:
        return []

    # Section headers
    sections_off = opt_off + opt_hdr_size
    sections = []
    for i in range(num_sections):
        s_off = sections_off + i * 40
        name = data[s_off:s_off+8].rstrip(b'\x00').decode('ascii', errors='replace')
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from('<IIII', data, s_off + 8)
        sections.append({
            'Name': name,
            'VirtualSize': vsize,
            'VirtualAddress': vaddr,
            'SizeOfRawData': raw_size,
            'PointerToRawData': raw_ptr,
        })

    # Convert export RVA to file offset
    export_off = rva_to_offset(export_rva, sections)
    if export_off is None:
        return []

    # Export directory structure (40 bytes)
    # Offset 0: Characteristics (4)
    # Offset 4: TimeDateStamp (4)
    # Offset 8: MajorVersion (2), MinorVersion (2)
    # Offset 12: Name RVA (4)
    # Offset 16: Base (4)
    # Offset 20: NumberOfFunctions (4)
    # Offset 24: NumberOfNames (4)
    # Offset 28: AddressOfFunctions RVA (4)
    # Offset 32: AddressOfNames RVA (4)
    # Offset 36: AddressOfNameOrdinals RVA (4)

    base_ordinal = struct.unpack_from('<I', data, export_off + 16)[0]
    num_names = struct.unpack_from('<I', data, export_off + 24)[0]
    names_rva = struct.unpack_from('<I', data, export_off + 32)[0]

    if num_names == 0:
        return []

    names_off = rva_to_offset(names_rva, sections)
    if names_off is None:
        return []

    # Read name pointers (array of RVAs)
    exports = []
    for i in range(num_names):
        name_rva = struct.unpack_from('<I', data, names_off + i * 4)[0]
        name_off = rva_to_offset(name_rva, sections)
        if name_off is not None:
            # Read null-terminated string
            end = data.index(b'\x00', name_off)
            name = data[name_off:end].decode('ascii', errors='replace')
            if name:
                exports.append(name)

    return exports

def main():
    system32 = r'C:\Windows\System32'
    rust_lld = os.path.join(
        os.environ.get('USERPROFILE', ''),
        '.rustup', 'toolchains', 'stable-x86_64-pc-windows-msvc',
        'lib', 'rustlib', 'x86_64-pc-windows-msvc', 'bin', 'rust-lld.exe'
    )
    if not os.path.exists(rust_lld):
        print(f"ERROR: rust-lld not found at {rust_lld}", file=sys.stderr)
        sys.exit(1)

    # Copy as lld-link.exe (auto-selects MSVC flavor)
    lld_link = os.path.join(os.path.dirname(__file__), 'lld-link.exe')
    if not os.path.exists(lld_link):
        import shutil
        shutil.copy2(rust_lld, lld_link)

    out_dir = os.path.join(os.path.dirname(__file__), 'winlibs')
    os.makedirs(out_dir, exist_ok=True)

    dlls = ['kernel32.dll', 'ntdll.dll', 'userenv.dll', 'ws2_32.dll', 'dbghelp.dll']

    for dll in dlls:
        dll_path = os.path.join(system32, dll)
        if not os.path.exists(dll_path):
            print(f"SKIP: {dll} not found", file=sys.stderr)
            continue

        exports = read_pe_exports(dll_path)
        if not exports:
            print(f"SKIP: No exports found in {dll}", file=sys.stderr)
            continue

        # Write .def file
        lib_name = dll.replace('.dll', '')
        def_path = os.path.join(out_dir, f'{lib_name}.def')
        with open(def_path, 'w') as f:
            f.write(f'LIBRARY {lib_name}\n')
            f.write('EXPORTS\n')
            for name in exports:
                f.write(f'  {name}\n')

        print(f"  {dll}: {len(exports)} exports -> {def_path}")

        # Generate .lib from .def using lld-link
        lib_path = os.path.join(out_dir, f'{lib_name}.lib')
        result = subprocess.run(
            [lld_link, '/lib', f'/def:{def_path}', f'/out:{lib_path}', '/machine:x64'],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"  ERROR generating {lib_name}.lib: {result.stderr}", file=sys.stderr)
        else:
            print(f"  OK: {lib_path}")

    print(f"\nDone. Import libraries in: {out_dir}")

if __name__ == '__main__':
    main()
