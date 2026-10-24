cmake_minimum_required(VERSION 3.22)
project(resonance_audio LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
include(FetchContent)

# Complete pinned source archives are shipped with the project, including licenses.
# No desktop executable or network download is needed by the APK at runtime.
FetchContent_Declare(utfcpp URL "${CMAKE_CURRENT_SOURCE_DIR}/vendor/utfcpp.tar.gz"
  URL_HASH SHA256=cb200230b7943749faf8600192a101e6e697ff238ccd107cff4346a172b49c29
  SOURCE_SUBDIR _headers_only)
FetchContent_MakeAvailable(utfcpp)
set(utf8cpp_INCLUDE_DIR "${utfcpp_SOURCE_DIR}/source" CACHE PATH "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_BINDINGS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(WITH_ZLIB OFF CACHE BOOL "" FORCE)
FetchContent_Declare(taglib URL "${CMAKE_CURRENT_SOURCE_DIR}/vendor/taglib.tar.gz"
  URL_HASH SHA256=aca955e8669ba7584a6271f6ee3933d3ac26c894db8c883b4b5d84d94d6545d1)
FetchContent_MakeAvailable(taglib)
FetchContent_Declare(chromaprint URL "${CMAKE_CURRENT_SOURCE_DIR}/vendor/chromaprint.tar.gz"
  URL_HASH SHA256=cbd6e623f458000a1c39ba724b85b031d324bdfc653e14d9b5e1d87c6a3bf7cd
  SOURCE_SUBDIR _populated_before_add)
FetchContent_MakeAvailable(chromaprint)
set(FFT_LIB kissfft CACHE STRING "" FORCE)
set(KISSFFT_ROOT "${chromaprint_SOURCE_DIR}/src/3rdparty/kissfft" CACHE PATH "" FORCE)
# Namespace conflicting optional upstream auxiliary targets in the build copy.
file(READ "${chromaprint_SOURCE_DIR}/CMakeLists.txt" chromaprint_cmake)
string(REPLACE "add_custom_target(uninstall" "add_custom_target(chromaprint_uninstall" chromaprint_cmake "${chromaprint_cmake}")
string(REPLACE "add_custom_target(docs" "add_custom_target(chromaprint_docs" chromaprint_cmake "${chromaprint_cmake}")
file(WRITE "${chromaprint_SOURCE_DIR}/CMakeLists.txt" "${chromaprint_cmake}")
add_subdirectory("${chromaprint_SOURCE_DIR}" "${chromaprint_BINARY_DIR}")

add_library(resonance_core STATIC audio_core.cpp)
target_link_libraries(resonance_core PUBLIC tag chromaprint)
target_compile_definitions(resonance_core PUBLIC CHROMAPRINT_NODLL)
target_include_directories(resonance_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${taglib_SOURCE_DIR}/taglib" "${taglib_SOURCE_DIR}/taglib/toolkit"
  "${taglib_BINARY_DIR}" "${taglib_BINARY_DIR}/taglib"
  "${chromaprint_SOURCE_DIR}/src")
if(ANDROID)
  add_library(resonance_audio SHARED jni_bridge.cpp)
  target_link_libraries(resonance_audio PRIVATE resonance_core log)
  # Compatible ELF alignment on devices using 16 KiB memory pages.
  target_link_options(resonance_audio PRIVATE "-Wl,-z,max-page-size=16384")
else()
  add_executable(resonance_desktop desktop_main.cpp)
  target_link_libraries(resonance_desktop PRIVATE resonance_core)
  add_executable(resonance_native_test tests/audio_test.cpp)
  target_link_libraries(resonance_native_test PRIVATE resonance_core)
endif()
