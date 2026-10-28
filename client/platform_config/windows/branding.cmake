# Keep the executable resource tied to the committed Resonance ICO.
set(_resonance_icon "${CMAKE_CURRENT_SOURCE_DIR}/../../platform_config/icons/windows/app_icon.ico")
if(NOT EXISTS "${_resonance_icon}")
  message(FATAL_ERROR "Resonance icon is missing. Restore the full source package.")
endif()
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/Runner.rc" _resonance_resources)
if(NOT _resonance_resources MATCHES "IDI_APP_ICON[^\n]*ICON[^\n]*resonance[.]ico")
  message(FATAL_ERROR "Windows icon resource was reset. Run python tools/bootstrap_client.py again.")
endif()
file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/resources")
configure_file("${_resonance_icon}" "${CMAKE_CURRENT_SOURCE_DIR}/resources/resonance.ico" COPYONLY)
configure_file("${_resonance_icon}" "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico" COPYONLY)
set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Runner.rc" APPEND PROPERTY
  OBJECT_DEPENDS "${_resonance_icon};${CMAKE_CURRENT_SOURCE_DIR}/resources/resonance.ico")
