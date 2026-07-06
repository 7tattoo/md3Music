cmake_minimum_required(VERSION 3.10)
project(nodejs_bridge)

set(NODE_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/include/node)

add_library(nodejs_bridge SHARED nodejs_bridge.cpp)
target_include_directories(nodejs_bridge PRIVATE ${NODE_INCLUDE_DIR})
target_link_libraries(nodejs_bridge log android)

set(NODE_LIB_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})
add_library(node SHARED IMPORTED)
set_target_properties(node PROPERTIES IMPORTED_LOCATION ${NODE_LIB_DIR}/libnode.so)
target_link_libraries(nodejs_bridge node)
