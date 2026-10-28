"""Bind committed brand assets to native executable/launcher resources."""
from pathlib import Path
import re
import shutil


def install_windows_branding(client: Path):
    runner = client / 'windows' / 'runner'
    rc = runner / 'Runner.rc'
    header = runner / 'resource.h'
    cmake = runner / 'CMakeLists.txt'
    # Fail rather than silently building with Flutter's default icon when a
    # future SDK template changes these integration points.
    text = rc.read_text(encoding='utf-8-sig')
    pattern = r'(?m)^([ \t]*IDI_APP_ICON[ \t]+ICON(?:[ \t]+DISCARDABLE)?[ \t]+)"[^"\r\n]+"([^\r\n]*)$'
    if len(re.findall(pattern, text)) != 1:
        raise RuntimeError('Cannot locate the Windows executable icon resource in Runner.rc.')
    if len(re.findall(r'(?m)^\s*#define\s+IDI_APP_ICON\s+101\s*$', header.read_text(encoding='utf-8-sig'))) != 1:
        raise RuntimeError('Windows resource.h must define IDI_APP_ICON as 101.')
    code = cmake.read_text()
    if 'Runner.rc' not in code:
        raise RuntimeError('The Windows runner must compile Runner.rc.')
    begin = '# BEGIN RESONANCE EXECUTABLE ICON'
    end = '# END RESONANCE EXECUTABLE ICON'
    if begin in code:
        block = re.compile(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', re.S)
        code, count = block.subn('', code)
        if count != 1 or begin in code:
            raise RuntimeError('Invalid Windows branding CMake block.')
    code = code.rstrip() + '\n\n' + begin + '\ninclude("${CMAKE_CURRENT_SOURCE_DIR}/resonance_branding.cmake")\n' + end + '\n'
    # Dedicated executable resource; app_icon is replaced too for compatibility.
    resource = runner / 'resources'
    resource.mkdir(parents=True, exist_ok=True)
    for name in ['app_icon.ico', 'resonance.ico']:
        shutil.copyfile(client / 'platform_config/icons/windows/app_icon.ico', resource / name)
    shutil.copyfile(client / 'platform_config/windows/branding.cmake', runner / 'resonance_branding.cmake')
    patched = re.sub(pattern, lambda m: m[1] + '"resources\\\\resonance.ico"' + m[2], text)
    bom = b'\xef\xbb\xbf' if rc.read_bytes().startswith(b'\xef\xbb\xbf') else b''
    rc.write_bytes(bom + patched.encode('utf-8'))
    cmake.write_text(code)


def install_branding(client: Path):
    install_windows_branding(client)
    shutil.copytree(client / 'platform_config/icons/android', client / 'android/app/src/main/res', dirs_exist_ok=True)
