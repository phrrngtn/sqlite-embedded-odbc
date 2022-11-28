cmake_minimum_required(VERSION 3.0)
project(sqlite-embedded-odbc)

find_package(unofficial-sqlite3 CONFIG REQUIRED)
find_path(SQLITE_INCLUDE_DIR sqlite3ext.h)
include_directories(${SQLITE_INCLUDE_DIR})

find_package(nanodbc CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)

add_library(embedded_odbc SHARED sqlite_embedded_odbc.cpp)
target_link_libraries(embedded_odbc PUBLIC nanodbc)

