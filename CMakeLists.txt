cmake_minimum_required(VERSION 3.24)

project(pdfview LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(pdfview_core INTERFACE)

target_include_directories(pdfview_core INTERFACE src)

if(APPLE)
    enable_language(OBJCXX)
    add_executable(pdfview_mac src/mac/main.mm)
    target_link_libraries(pdfview_mac PRIVATE pdfview_core "-framework AppKit")
elseif(WIN32)
    add_executable(pdfview_win WIN32 src/win/main.cpp)
    target_link_libraries(pdfview_win PRIVATE pdfview_core)
endif()
