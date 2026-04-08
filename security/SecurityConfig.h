// =============================================================================
// SecurityConfig.h
//
// Interfaz pública de la infraestructura de seguridad para FastDDS.
// Proporciona herramientas para la validación de artefactos PKI y la inyección
// de plugins DDS-Security en el QoS del DomainParticipant.
//
// Escenarios soportados:
//   "none"    → Sin seguridad.
//   "auth"    → Autenticación mutua PKI-DH (RSA-3072), sin cifrado.
//   "encrypt" → Autenticación + cifrado total AES-GCM-256.
//   "access"  → Autenticación + cifrado + control de acceso granular por tópico.
//
// Compatible con: eProsima FastDDS 2.x
// Estándar:       OMG DDS Security v1.1
// =============================================================================

#ifndef SECURITY_CONFIG_H
#define SECURITY_CONFIG_H

#include <string>
#include <fastdds/dds/domain/qos/DomainParticipantQos.hpp>

namespace security {

/**
 * @brief Verifica la integridad y existencia de los archivos de seguridad.
 * * Realiza una comprobación preventiva en el sistema de archivos antes de
 * inicializar el DomainParticipant. Esto evita fallos de segmentación si los
 * certificados no fueron generados o copiados correctamente.
 *
 * @param escenario "none" | "auth" | "encrypt" | "access"
 * @param rol       "publisher" | "subscriber"
 * @param security_dir Directorio raíz de seguridad (por defecto: "security")
 * @return true si todos los archivos necesarios están presentes, false en caso contrario.
 */
bool validate_artifacts(
    const std::string& escenario,
    const std::string& rol,
    const std::string& security_dir = "security"
);

/**
 * @brief Configura los plugins DDS-Security en el QoS del participante.
 *
 * Inyecta las propiedades de autenticación (PKI-DH), control de acceso
 * (Access-Permissions) y criptografía (AES-GCM-GMAC) según el escenario.
 *
 * @param pqos      QoS del participante que será modificado in-place.
 * @param escenario Escenario de seguridad a aplicar.
 * @param rol       Rol del nodo para seleccionar las claves correctas.
 * @param security_dir Directorio base de los artefactos.
 * * @throws std::runtime_error si validate_artifacts falla para escenarios != "none".
 * @throws std::invalid_argument si los parámetros de entrada son desconocidos.
 */
void configure_security_qos(
    eprosima::fastdds::dds::DomainParticipantQos& pqos,
    const std::string& escenario,
    const std::string& rol           = "publisher",
    const std::string& security_dir  = "security"
);

} // namespace security

#endif // SECURITY_CONFIG_H
