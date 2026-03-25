# ==============================================================================
#  CMakeLists.txt — Proyecto DDS-Security / Payload benchmark
#
#  Añadido respecto a la versión original:
#    · Directorio raíz del proyecto como include_directories para que los
#      #include "security/SecurityConfig.h" se resuelvan correctamente desde
#      cualquier fichero fuente.
#    · security/SecurityConfig.cxx añadido a las fuentes del ejecutable.
#    · target_include_directories explícito en el ejecutable principal.
# ==============================================================================

cmake_minimum_required(VERSION 2.8.12)

project("generated_code")

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_EXTENSIONS OFF)

# ------------------------------------------------------------------------------
# Dependencias externas
# Requiere FastDDS (fastrtps) y FastCDR instalados, por ejemplo a través de
# ROS 2 Humble:
#   cmake -DCMAKE_PREFIX_PATH=/opt/ros/humble ..
# ------------------------------------------------------------------------------
find_package(fastcdr REQUIRED)
find_package(fastrtps REQUIRED)

# ------------------------------------------------------------------------------
# Directorio raíz como include base global
# Permite usar rutas absolutas-desde-raíz en los #include:
#   #include "security/SecurityConfig.h"    ← desde payloadPublisher.cxx
#   #include "security/SecurityConfig.h"    ← desde payloadSubscriber.cxx
# ------------------------------------------------------------------------------
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# ------------------------------------------------------------------------------
# Librería auxiliar: serialización del tipo IDL 'payload'
# Generada por fastcdrgen; contiene el código CDR de Payload.
# ------------------------------------------------------------------------------
message(STATUS "Configuring payload_lib (IDL type support)...")

add_library(payload_lib
    payload.cxx
)
target_link_libraries(payload_lib
    fastcdr
    fastrtps
)

# ------------------------------------------------------------------------------
# Ejecutable principal: payload
#
# Fuentes:
#   payloadPubSubTypes.cxx  — Registro del tipo DDS (TypeSupport)
#   payloadPublisher.cxx    — Lógica del publicador
#   payloadSubscriber.cxx   — Lógica del suscriptor
#   payloadPubSubMain.cxx   — Punto de entrada CLI
#   security/SecurityConfig.cxx — Configuración de plugins DDS-Security
#
# Uso del binario compilado:
#   ./payload publisher [muestras] [bytes] [espera_us] [escenario]
#   ./payload subscriber [escenario]
#
# Escenarios: none | auth | encrypt | access
# IMPORTANTE: ejecutar siempre desde la raíz del proyecto (/app en Docker)
#             para que las rutas relativas a security/pki/ y security/signed/
#             se resuelvan correctamente.
# ------------------------------------------------------------------------------
message(STATUS "Configuring payload executable (with DDS-Security support)...")

add_executable(payload
    payloadPubSubTypes.cxx
    payloadPublisher.cxx
    payloadSubscriber.cxx
    payloadPubSubMain.cxx
    security/SecurityConfig.cxx         # Plugins: PKI-DH, Access-Permissions, AES-GCM-GMAC
)

# El ejecutable necesita ver los headers desde la raíz del proyecto.
# Esto es redundante si ya se usó include_directories() arriba, pero
# es la forma moderna y explícita recomendada por CMake >= 2.8.12.
target_include_directories(payload PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(payload
    fastcdr
    fastrtps
    payload_lib
)
