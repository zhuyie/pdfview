cmake_minimum_required(VERSION 3.24)

project(pdfview LANGUAGES CXX)

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
    src/core/page_cache.cpp
    src/core/pdfium_document.cpp
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

if(APPLE)
    enable_language(OBJCXX)
    add_executable(pdfview_mac src/mac/main.mm)
    target_link_libraries(pdfview_mac PRIVATE pdfview_core "-framework AppKit" "-framework UniformTypeIdentifiers")
    add_custom_command(TARGET pdfview_mac POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${PDFIUM_ROOT}/lib/libpdfium.dylib"
            "$<TARGET_FILE_DIR:pdfview_mac>/libpdfium.dylib"
        COMMAND install_name_tool -id "@executable_path/libpdfium.dylib"
            "$<TARGET_FILE_DIR:pdfview_mac>/libpdfium.dylib"
        COMMAND install_name_tool -change "./libpdfium.dylib" "@executable_path/libpdfium.dylib"
            "$<TARGET_FILE:pdfview_mac>"
    )
elseif(WIN32)
    add_executable(pdfview_win WIN32 src/win/main.cpp)
    target_link_libraries(pdfview_win PRIVATE pdfview_core)
    add_custom_command(TARGET pdfview_win POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${PDFIUM_ROOT}/bin/pdfium.dll"
            "$<TARGET_FILE_DIR:pdfview_win>/pdfium.dll"
    )
endif()
