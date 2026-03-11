cmake_minimum_required(VERSION 3.21)
project(opm_godot_orchestrator VERSION 0.1.0 LANGUAGES NONE)

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
set(OPM_TARGET_PLATFORM "linux" CACHE STRING "Target platform (linux|windows|macos|web|android|ios)")
set_property(CACHE OPM_TARGET_PLATFORM PROPERTY STRINGS linux windows macos web android ios)

set(OPM_BUILD_VARIANT "debug" CACHE STRING "Build variant (debug|release)")
set_property(CACHE OPM_BUILD_VARIANT PROPERTY STRINGS debug release)

set(OPM_ASSET_PATH "" CACHE PATH "Optional game asset path for web workflows")
set(OPM_EMSDK_DIR "$ENV{HOME}/emsdk" CACHE PATH "Path to emsdk root directory")
set(OPM_GODOT_EXPORT_PRESET "" CACHE STRING "Override Godot export preset name")
set(OPM_GODOT_EXPORT_OUTPUT "" CACHE STRING "Override Godot export output path")
set(OPM_ARCH "" CACHE STRING "Architecture hint (macOS cross builds)")

set(OPM_ROOT "${CMAKE_SOURCE_DIR}")
set(OPM_SCRIPT_DIR "${OPM_ROOT}/scripts")
set(OPM_DIST_DIR "${OPM_ROOT}/dist/${OPM_TARGET_PLATFORM}/${OPM_BUILD_VARIANT}")
set(OPM_SHELL "bash")

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function(opm_add_script_target name)
    cmake_parse_arguments(ARG "" "WORKING_DIRECTORY" "COMMAND" ${ARGN})
    if(NOT ARG_WORKING_DIRECTORY)
        set(ARG_WORKING_DIRECTORY "${OPM_ROOT}")
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
if(OPM_TARGET_PLATFORM STREQUAL "linux" OR OPM_TARGET_PLATFORM STREQUAL "windows" OR OPM_TARGET_PLATFORM STREQUAL "macos")
    if(OPM_BUILD_VARIANT STREQUAL "release")
        set(_variant_args "target=template_release")
    else()
        set(_variant_args "target=template_debug")
    endif()

    set(_desktop_args "${OPM_TARGET_PLATFORM}" "${_variant_args}")
    if(OPM_ARCH)
        list(APPEND _desktop_args "arch=${OPM_ARCH}")
    endif()

    opm_add_script_target(opm-engine
        COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/build-desktop.sh" ${_desktop_args}
    )
elseif(OPM_TARGET_PLATFORM STREQUAL "web")
    if(OPM_BUILD_VARIANT STREQUAL "release")
        set(_web_variant "--release")
    else()
        set(_web_variant "--debug")
    endif()

    opm_add_script_target(opm-engine
        COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/build-web.sh" "--build-only" "${_web_variant}" "--emsdk" "${OPM_EMSDK_DIR}"
    )
else()
    opm_add_script_target(opm-engine
        COMMAND "${CMAKE_COMMAND}" -E echo "Engine build for ${OPM_TARGET_PLATFORM} is not wired yet."
    )
endif()

# ---------------------------------------------------------------------------
# 2) Godot export → dist/<platform>/<variant>/
# ---------------------------------------------------------------------------
set(_export_args "--platform" "${OPM_TARGET_PLATFORM}" "--variant" "${OPM_BUILD_VARIANT}")
if(OPM_GODOT_EXPORT_PRESET)
    list(APPEND _export_args "--preset" "${OPM_GODOT_EXPORT_PRESET}")
endif()
if(OPM_GODOT_EXPORT_OUTPUT)
    list(APPEND _export_args "--output" "${OPM_GODOT_EXPORT_OUTPUT}")
endif()

opm_add_script_target(opm-export
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/export-godot.sh" ${_export_args}
)

if(OPM_TARGET_PLATFORM STREQUAL "web")
    add_dependencies(opm-export opm-engine)
endif()

# ---------------------------------------------------------------------------
# 3) Full web pipeline (engine + export + JS patches)
# ---------------------------------------------------------------------------
if(OPM_TARGET_PLATFORM STREQUAL "web")
    set(_web_full_args)
    if(OPM_BUILD_VARIANT STREQUAL "release")
        list(APPEND _web_full_args "--release")
    else()
        list(APPEND _web_full_args "--debug")
    endif()
    list(APPEND _web_full_args "--emsdk" "${OPM_EMSDK_DIR}")
    if(OPM_ASSET_PATH)
        list(APPEND _web_full_args "--asset-path" "${OPM_ASSET_PATH}")
    endif()

    opm_add_script_target(opm-web-export
        COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/build-web.sh" ${_web_full_args}
    )
endif()

# ---------------------------------------------------------------------------
# 4) Signing / packaging
# ---------------------------------------------------------------------------
opm_add_script_target(opm-sign-android
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/sign-android.sh"
)

opm_add_script_target(opm-sign-ios
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/sign-ios.sh"
)

opm_add_script_target(opm-package
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/package-build.sh" "--platform" "${OPM_TARGET_PLATFORM}" "--variant" "${OPM_BUILD_VARIANT}"
)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
message(STATUS "Configured OpenMoHAA/Godot orchestrator")
message(STATUS "  Platform = ${OPM_TARGET_PLATFORM}")
message(STATUS "  Variant  = ${OPM_BUILD_VARIANT}")
message(STATUS "  Dist     = ${OPM_DIST_DIR}")
message(STATUS "  Targets: opm-engine, opm-export, opm-package, opm-sign-android, opm-sign-ios")
if(OPM_TARGET_PLATFORM STREQUAL "web")
    message(STATUS "  Additional: opm-web-export")
endif()
