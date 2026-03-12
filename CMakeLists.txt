cmake_minimum_required(VERSION 3.21)
project(mohaa_godot_orchestrator VERSION 0.1.0 LANGUAGES NONE)

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
set(MOHAA_TARGET_PLATFORM "linux" CACHE STRING "Target platform (linux|windows|macos|web|android|ios)")
set_property(CACHE MOHAA_TARGET_PLATFORM PROPERTY STRINGS linux windows macos web android ios)

set(MOHAA_BUILD_VARIANT "debug" CACHE STRING "Build variant (debug|release)")
set_property(CACHE MOHAA_BUILD_VARIANT PROPERTY STRINGS debug release)

set(MOHAA_ASSET_PATH "" CACHE PATH "Optional game asset path for web workflows")
set(MOHAA_EMSDK_DIR "$ENV{HOME}/emsdk" CACHE PATH "Path to emsdk root directory")
set(MOHAA_GODOT_EXPORT_PRESET "" CACHE STRING "Override Godot export preset name")
set(MOHAA_GODOT_EXPORT_OUTPUT "" CACHE STRING "Override Godot export output path")
set(MOHAA_ARCH "" CACHE STRING "Architecture hint (macOS cross builds)")

set(MOHAA_ROOT "${CMAKE_SOURCE_DIR}")
set(MOHAA_SCRIPT_DIR "${MOHAA_ROOT}/scripts")
set(MOHAA_DIST_DIR "${MOHAA_ROOT}/dist/${MOHAA_TARGET_PLATFORM}/${MOHAA_BUILD_VARIANT}")
set(MOHAA_SHELL "bash")

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function(mohaa_add_script_target name)
    cmake_parse_arguments(ARG "" "WORKING_DIRECTORY" "COMMAND" ${ARGN})
    if(NOT ARG_WORKING_DIRECTORY)
        set(ARG_WORKING_DIRECTORY "${MOHAA_ROOT}")
    endif()
    add_custom_target(${name}
        COMMAND ${ARG_COMMAND}
        WORKING_DIRECTORY "${ARG_WORKING_DIRECTORY}"
        USES_TERMINAL
        VERBATIM
    )
endfunction()

# ---------------------------------------------------------------------------
# 1) Engine build
# ---------------------------------------------------------------------------
if(MOHAA_TARGET_PLATFORM STREQUAL "linux" OR MOHAA_TARGET_PLATFORM STREQUAL "windows" OR MOHAA_TARGET_PLATFORM STREQUAL "macos")
    if(MOHAA_BUILD_VARIANT STREQUAL "release")
        set(_variant_args "target=template_release")
    else()
        set(_variant_args "target=template_debug")
    endif()

    set(_desktop_args "${MOHAA_TARGET_PLATFORM}" "${_variant_args}")
    if(MOHAA_ARCH)
        list(APPEND _desktop_args "arch=${MOHAA_ARCH}")
    endif()

    mohaa_add_script_target(mohaa-engine
        COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/build-desktop.sh" ${_desktop_args}
    )
elseif(MOHAA_TARGET_PLATFORM STREQUAL "web")
    if(MOHAA_BUILD_VARIANT STREQUAL "release")
        set(_web_variant "--release")
    else()
        set(_web_variant "--debug")
    endif()

    mohaa_add_script_target(mohaa-engine
        COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/build-web.sh" "--build-only" "${_web_variant}" "--emsdk" "${MOHAA_EMSDK_DIR}"
    )
else()
    mohaa_add_script_target(mohaa-engine
        COMMAND "${CMAKE_COMMAND}" -E echo "Engine build for ${MOHAA_TARGET_PLATFORM} is not wired yet."
    )
endif()

# ---------------------------------------------------------------------------
# 2) Godot export → dist/<platform>/<variant>/
# ---------------------------------------------------------------------------
set(_export_args "--platform" "${MOHAA_TARGET_PLATFORM}" "--variant" "${MOHAA_BUILD_VARIANT}")
if(MOHAA_GODOT_EXPORT_PRESET)
    list(APPEND _export_args "--preset" "${MOHAA_GODOT_EXPORT_PRESET}")
endif()
if(MOHAA_GODOT_EXPORT_OUTPUT)
    list(APPEND _export_args "--output" "${MOHAA_GODOT_EXPORT_OUTPUT}")
endif()

mohaa_add_script_target(mohaa-export
    COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/export-godot.sh" ${_export_args}
)

if(MOHAA_TARGET_PLATFORM STREQUAL "web")
    add_dependencies(mohaa-export mohaa-engine)
endif()

# ---------------------------------------------------------------------------
# 3) Full web pipeline (engine + export + JS patches)
# ---------------------------------------------------------------------------
if(MOHAA_TARGET_PLATFORM STREQUAL "web")
    set(_web_full_args)
    if(MOHAA_BUILD_VARIANT STREQUAL "release")
        list(APPEND _web_full_args "--release")
    else()
        list(APPEND _web_full_args "--debug")
    endif()
    list(APPEND _web_full_args "--emsdk" "${MOHAA_EMSDK_DIR}")
    if(MOHAA_ASSET_PATH)
        list(APPEND _web_full_args "--asset-path" "${MOHAA_ASSET_PATH}")
    endif()

    mohaa_add_script_target(mohaa-web-export
        COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/build-web.sh" ${_web_full_args}
    )
endif()

# ---------------------------------------------------------------------------
# 4) Signing / packaging
# ---------------------------------------------------------------------------
mohaa_add_script_target(mohaa-sign-android
    COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/sign-android.sh"
)

mohaa_add_script_target(mohaa-sign-ios
    COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/sign-ios.sh"
)

mohaa_add_script_target(mohaa-package
    COMMAND "${MOHAA_SHELL}" "${MOHAA_SCRIPT_DIR}/package-build.sh" "--platform" "${MOHAA_TARGET_PLATFORM}" "--variant" "${MOHAA_BUILD_VARIANT}"
)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
message(STATUS "Configured OpenMoHAA/Godot orchestrator")
message(STATUS "  Platform = ${MOHAA_TARGET_PLATFORM}")
message(STATUS "  Variant  = ${MOHAA_BUILD_VARIANT}")
message(STATUS "  Dist     = ${MOHAA_DIST_DIR}")
message(STATUS "  Targets: mohaa-engine, mohaa-export, mohaa-package, mohaa-sign-android, mohaa-sign-ios")
if(MOHAA_TARGET_PLATFORM STREQUAL "web")
    message(STATUS "  Additional: mohaa-web-export")
endif()
