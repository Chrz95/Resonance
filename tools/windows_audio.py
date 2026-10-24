"""Install SDK-compatible build rules for the portable Windows audio helper."""
from pathlib import Path


def install_windows_audio(client: Path):
    file = client / "windows" / "CMakeLists.txt"
    code = file.read_text()
    marker = "# BEGIN RESONANCE DESKTOP AUDIO"
    if marker in code:
        code = code[:code.index(marker)].rstrip() + "\n"
    code += '\n' + marker + '''
# The same TagLib/Chromaprint sources are built for Android and Windows.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native" "${CMAKE_CURRENT_BINARY_DIR}/resonance_audio" EXCLUDE_FROM_ALL)
add_dependencies(${BINARY_NAME} resonance_desktop)
install(TARGETS resonance_desktop RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/tools" COMPONENT Runtime)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../windows_tools/ffmpeg/"
        DESTINATION "${CMAKE_INSTALL_PREFIX}/tools" COMPONENT Runtime)
# END RESONANCE DESKTOP AUDIO
'''
    file.write_text(code)
