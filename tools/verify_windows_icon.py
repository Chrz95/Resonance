#!/usr/bin/env python3
"""Check the compiled Windows EXE's icon bytes without executing the program."""
import argparse
import ctypes
from pathlib import Path
import struct
import sys


def ico_images(path):
    data = Path(path).read_bytes()
    reserved, kind, count = struct.unpack_from('<HHH', data)
    if reserved or kind != 1 or count < 1:
        raise ValueError('Invalid source ICO.')
    images = []
    for index in range(count):
        entry = struct.unpack_from('<BBBBHHII', data, 6 + index * 16)
        size, offset = entry[-2:]
        if offset + size > len(data) or size == 0:
            raise ValueError('Truncated source ICO.')
        images.append((entry[:6], data[offset:offset + size]))
    return images


def verify_group(group, load_image, expected):
    reserved, kind, count = struct.unpack_from('<HHH', group)
    if reserved or kind != 1 or count != len(expected) or len(group) != 6 + count * 14:
        raise ValueError('EXE icon group differs from Resonance ICO.')
    for index, (metadata, payload) in enumerate(expected):
        entry = struct.unpack_from('<BBBBHHIH', group, 6 + index * 14)
        if entry[:2] != metadata[:2] or entry[6] != len(payload) or load_image(entry[7]) != payload:
            raise ValueError('EXE contains different icon artwork. Rebuild with the Resonance resource.')


def verify_executable(exe, icon):
    if sys.platform != 'win32':
        raise RuntimeError('Compiled EXE verification must run on Windows.')
    from ctypes import wintypes as w
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [w.LPCWSTR, w.HANDLE, w.DWORD]
    kernel.LoadLibraryExW.restype = w.HMODULE
    kernel.FindResourceW.argtypes = [w.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    kernel.FindResourceW.restype = w.HANDLE
    kernel.LoadResource.argtypes = [w.HMODULE, w.HANDLE]
    kernel.LoadResource.restype = w.HANDLE
    kernel.LockResource.argtypes = [w.HANDLE]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.SizeofResource.argtypes = [w.HMODULE, w.HANDLE]
    kernel.SizeofResource.restype = w.DWORD
    kernel.FreeLibrary.argtypes = [w.HMODULE]
    kernel.FreeLibrary.restype = w.BOOL
    module = kernel.LoadLibraryExW(str(Path(exe).resolve()), None, 0x02 | 0x20)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        def resource(kind, identifier):
            found = kernel.FindResourceW(module, ctypes.c_void_p(identifier), ctypes.c_void_p(kind))
            if not found:
                raise ctypes.WinError(ctypes.get_last_error())
            size = kernel.SizeofResource(module, found)
            loaded = kernel.LoadResource(module, found)
            pointer = kernel.LockResource(loaded)
            if not size or not pointer:
                raise ValueError('Empty executable icon resource.')
            return ctypes.string_at(pointer, size)
        callback_type = ctypes.WINFUNCTYPE(w.BOOL, w.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ssize_t)
        names = []
        def found_name(module, kind, name, parameter):
            names.append(name if name <= 65535 else ctypes.wstring_at(name))
            return True
        callback = callback_type(found_name)
        kernel.EnumResourceNamesW.argtypes = [w.HMODULE, ctypes.c_void_p, callback_type, ctypes.c_ssize_t]
        kernel.EnumResourceNamesW.restype = w.BOOL
        if not kernel.EnumResourceNamesW(module, ctypes.c_void_p(14), callback, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        if names != [101]:
            raise ValueError('Expected only the Resonance application icon group (101).')
        verify_group(resource(14, 101), lambda identifier: resource(3, identifier), ico_images(icon))
    finally:
        kernel.FreeLibrary(module)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exe', type=Path)
    parser.add_argument('--icon', type=Path, default=Path(__file__).resolve().parents[1] / 'client/platform_config/icons/windows/app_icon.ico')
    args = parser.parse_args()
    verify_executable(args.exe, args.icon)
    print('Verified: Windows EXE embeds the Resonance icon at every supplied size.')


if __name__ == '__main__':
    main()
