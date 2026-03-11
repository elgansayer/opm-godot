cmake_minimum_required(VERSION 3.21)

project(opm_godot_orchestrator VERSION 0.1.0 LANGUAGES NONE)

# High-level orchestration only. Engine compilation remains delegated to the
# existing per-platform scripts until native CMake build parity is complete.
set(OPM_TARGET_PLATFORM "linux" CACHE STRING "Target platform (linux|windows|macos|web|android|ios)")
set_property(CACHE OPM_TARGET_PLATFORM PROPERTY STRINGS linux windows macos web android ios)

set(OPM_BUILD_VARIANT "debug" CACHE STRING "Build variant (debug|release)")
set_property(CACHE OPM_BUILD_VARIANT PROPERTY STRINGS debug release)

set(OPM_ASSET_PATH "" CACHE PATH "Optional game asset path for web serve/export workflows")
set(OPM_EMSDK_DIR "$ENV{HOME}/emsdk" CACHE PATH "Path to emsdk root directory")
option(OPM_WEB_MINIMAL "Use minimal web export path (skip custom runtime patching)" OFF)
set(OPM_GODOT_EXPORT_PRESET "" CACHE STRING "Optional explicit Godot export preset override")
set(OPM_GODOT_EXPORT_OUTPUT "" CACHE STRING "Optional output path override for Godot export")
set(OPM_ARCH "" CACHE STRING "Optional architecture hint (for macOS cross builds)")

set(OPM_ROOT "${CMAKE_SOURCE_DIR}")
set(OPM_SCRIPT_DIR "${OPM_ROOT}/scripts")

if(WIN32)
    set(OPM_SHELL "bash")
else()
    set(OPM_SHELL "bash")
endif()

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

# 1) Engine/native build orchestration
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
        COMMAND "${CMAKE_COMMAND}" -E echo "Engine native build for ${OPM_TARGET_PLATFORM} is not wired yet; run export/sign targets for platform packaging."
    )
endif()

# 2) Godot CLI export orchestration (separate from engine build)
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

# Web export requires a freshly built wasm GDExtension in project/bin.
if(OPM_TARGET_PLATFORM STREQUAL "web")
    add_dependencies(opm-export opm-engine)
endif()

# 3) Web convenience target for full web export/runtime patching and optional asset prep
if(OPM_TARGET_PLATFORM STREQUAL "web")
    set(_web_full_args)
    if(OPM_BUILD_VARIANT STREQUAL "release")
        list(APPEND _web_full_args "--release")
    else()
        list(APPEND _web_full_args "--debug")
    endif()
    list(APPEND _web_full_args "--emsdk" "${OPM_EMSDK_DIR}")
    if(OPM_WEB_MINIMAL)
        list(APPEND _web_full_args "--minimal")
    endif()
    if(OPM_ASSET_PATH)
        list(APPEND _web_full_args "--asset-path" "${OPM_ASSET_PATH}")
    endif()

    opm_add_script_target(opm-web-export
        COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/build-web.sh" ${_web_full_args}
    )
endif()

# 4) Thin signing/provisioning wrappers
opm_add_script_target(opm-sign-android
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/sign-android.sh"
)

opm_add_script_target(opm-sign-ios
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/sign-ios.sh"
)

# 5) Thin package/deploy wrapper
opm_add_script_target(opm-package
    COMMAND "${OPM_SHELL}" "${OPM_SCRIPT_DIR}/package-build.sh" "--platform" "${OPM_TARGET_PLATFORM}" "--variant" "${OPM_BUILD_VARIANT}"
)

message(STATUS "Configured OpenMoHAA/Godot orchestrator")
message(STATUS "  OPM_TARGET_PLATFORM = ${OPM_TARGET_PLATFORM}")
message(STATUS "  OPM_BUILD_VARIANT   = ${OPM_BUILD_VARIANT}")
message(STATUS "  OPM_EMSDK_DIR       = ${OPM_EMSDK_DIR}")
message(STATUS "Targets: opm-engine, opm-export, opm-package, opm-sign-android, opm-sign-ios")
if(OPM_TARGET_PLATFORM STREQUAL "web")
    message(STATUS "Additional target: opm-web-export")
endif()
