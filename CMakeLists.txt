cmake_minimum_required(VERSION 3.24)

project(pdfview LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(PDFIUM_ROOT "" CACHE PATH "Path to a PDFium distribution root")

if(PDFIUM_ROOT STREQUAL "")
    if(APPLE)
        set(PDFIUM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/pdfium/mac-univ")
    elseif(WIN32)
        set(PDFIUM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/pdfium/win-x64")
    endif()
endif()

add_library(pdfview_core
    src/core/document.cpp
    src/core/document_paths.cpp
    src/core/document_view_model.cpp
    src/core/page_cache.cpp
    src/core/profiling.cpp
    src/core/pdfium_document.cpp
    src/core/recent_documents.cpp
    src/core/viewport.cpp
)

target_include_directories(pdfview_core PUBLIC src)

find_path(PDFIUM_INCLUDE_DIR
    NAMES fpdfview.h
    HINTS
        "${PDFIUM_ROOT}/include"
)

find_library(PDFIUM_LIBRARY
    NAMES pdfium
    HINTS
        "${PDFIUM_ROOT}/lib"
        "${PDFIUM_ROOT}/lib/mac"
        "${PDFIUM_ROOT}/lib/win"
        "${PDFIUM_ROOT}/bin"
)

if(NOT PDFIUM_INCLUDE_DIR OR NOT PDFIUM_LIBRARY)
    message(FATAL_ERROR "PDFium headers or library were not found. Set PDFIUM_ROOT to a valid distribution.")
endif()

target_include_directories(pdfview_core PRIVATE "${PDFIUM_INCLUDE_DIR}")
target_link_libraries(pdfview_core PUBLIC "${PDFIUM_LIBRARY}")

function(pdfview_bundle_pdfium_runtime target_name)
    if(APPLE)
        add_custom_command(TARGET ${target_name} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${PDFIUM_ROOT}/lib/libpdfium.dylib"
                "$<TARGET_FILE_DIR:${target_name}>/libpdfium.dylib"
            COMMAND install_name_tool -id "@executable_path/libpdfium.dylib"
                "$<TARGET_FILE_DIR:${target_name}>/libpdfium.dylib"
            COMMAND install_name_tool -change "./libpdfium.dylib" "@executable_path/libpdfium.dylib"
                "$<TARGET_FILE:${target_name}>"
        )
    elseif(WIN32)
        add_custom_command(TARGET ${target_name} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${PDFIUM_ROOT}/bin/pdfium.dll"
                "$<TARGET_FILE_DIR:${target_name}>/pdfium.dll"
        )
    endif()
endfunction()

if(BUILD_TESTING)
    add_executable(pdfview_core_logic_tests tests/core_logic_tests.cpp)
    target_link_libraries(pdfview_core_logic_tests PRIVATE pdfview_core)
    add_test(NAME pdfview_core_logic_tests COMMAND pdfview_core_logic_tests)

    add_executable(pdfview_core_smoke tests/core_smoke.cpp)
    target_link_libraries(pdfview_core_smoke PRIVATE pdfview_core)
    pdfview_bundle_pdfium_runtime(pdfview_core_smoke)
    add_test(NAME pdfview_core_smoke
        COMMAND pdfview_core_smoke "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/smoke.pdf"
    )
endif()

if(APPLE)
    enable_language(OBJCXX)
    set(PDFVIEW_MAC_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/pdfview.icns")
    set(PDFVIEW_MAC_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/resources/Info.plist.in")
    set_source_files_properties("${PDFVIEW_MAC_ICON}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    add_executable(pdfview_mac MACOSX_BUNDLE
        "${PDFVIEW_MAC_ICON}"
        src/mac/app_delegate.mm
        src/mac/image_bridge.mm
        src/mac/main.mm
        src/mac/page_view_host.mm
        src/mac/render_coordinator.mm
        src/mac/tab_context.mm
    )
    target_link_libraries(pdfview_mac PRIVATE pdfview_core "-framework AppKit" "-framework UniformTypeIdentifiers")
    set_target_properties(pdfview_mac PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "pdfview"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.pdfview.app"
        MACOSX_BUNDLE_ICON_FILE "pdfview.icns"
        MACOSX_BUNDLE_INFO_PLIST "${PDFVIEW_MAC_INFO_PLIST}"
    )
    pdfview_bundle_pdfium_runtime(pdfview_mac)
elseif(WIN32)
    add_executable(pdfview_win WIN32 src/win/main.cpp)
    target_link_libraries(pdfview_win PRIVATE pdfview_core)
    pdfview_bundle_pdfium_runtime(pdfview_win)
endif()
