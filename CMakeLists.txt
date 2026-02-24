
cmake_minimum_required(VERSION 2.8.12)

project("generated_code")

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_EXTENSIONS OFF)

# Find requirements
find_package(fastcdr REQUIRED)
find_package(fastrtps REQUIRED)


message(STATUS "Configuring payload...")
add_library(payload_lib payload.cxx)
target_link_libraries(payload_lib fastcdr fastrtps)

add_executable(payload payloadPubSubTypes.cxx payloadPublisher.cxx payloadSubscriber.cxx payloadPubSubMain.cxx)
target_link_libraries(payload fastcdr fastrtps
        payload_lib )



