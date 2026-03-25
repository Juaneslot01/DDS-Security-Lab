// =============================================================================
// SecurityConfig.h
//
// Interfaz pública de la función auxiliar de seguridad DDS-Security.
// Inyecta los plugins de autenticación, control de acceso y cifrado en el
// DomainParticipantQos de FastDDS según el escenario seleccionado por CLI.
//
// Escenarios soportados:
//   "none"    → Sin seguridad (retorna sin modificar el QoS).
//   "auth"    → Autenticación mutua PKI-DH, sin cifrado.
//   "encrypt" → Autenticación + cifrado total AES-GCM-GMAC.
//   "access"  → Autenticación + cifrado + control de acceso por tópico.
//
// Roles soportados:
//   "publisher"  → Usa publisher_cert.pem / publisher_key.pem + permissions_pub.p7s
//   "subscriber" → Usa subscriber_cert.pem / subscriber_key.pem + permissions_sub.p7s
//
// Artefactos esperados en disco (generados por generate_security_artifacts.sh):
//   <security_dir>/pki/maincacert.pem
//   <security_dir>/pki/<rol>_cert.pem
//   <security_dir>/pki/<rol>_key.pem
//   <security_dir>/signed/gov_<escenario>.p7s
//   <security_dir>/signed/permissions_<pub|sub>.p7s
//
// IMPORTANTE: El binario debe ejecutarse desde la raíz del proyecto para que
//             las rutas relativas a los artefactos se resuelvan correctamente.
//             (p. ej.: /app dentro del contenedor Docker)
// =============================================================================

#ifndef SECURITY_CONFIG_H
#define SECURITY_CONFIG_H

#include <string>

#include <fastdds/dds/domain/qos/DomainParticipantQos.hpp>

namespace security {

// =============================================================================
// configure_security_qos
// -----------------------------------------------------------------------------
// Configura los plugins de seguridad DDS-Security en el QoS de un
// DomainParticipant de FastDDS según el escenario y el rol indicados.
//
// La función es IDEMPOTENTE respecto al escenario "none": retorna sin
// modificar pqos, permitiendo un binario único que funcione con o sin
// seguridad según el argumento de consola.
//
// Plugins configurados (para escenarios != "none"):
//   1. dds.sec.auth.plugin    → builtin.PKI-DH
//      Autenticación mutua mediante certificados X.509 y Diffie-Hellman.
//
//   2. dds.sec.access.plugin  → builtin.Access-Permissions
//      Verificación de gobernanza y permisos firmados con S/MIME (CMS).
//
//   3. dds.sec.crypto.plugin  → builtin.AES-GCM-GMAC  (solo encrypt/access)
//      Cifrado autenticado AEAD sobre datos y metadatos RTPS.
//
// Parámetros:
//   @param pqos         QoS del participante que será modificado in-place.
//   @param escenario    "none" | "auth" | "encrypt" | "access"
//   @param rol          "publisher" | "subscriber"
//   @param security_dir Directorio raíz de los artefactos de seguridad.
//                       Relativo al CWD del proceso. Por defecto: "security".
//
// Excepciones:
//   @throws std::invalid_argument  Si escenario o rol tienen un valor inválido.
// =============================================================================
void configure_security_qos(
    eprosima::fastdds::dds::DomainParticipantQos& pqos,
    const std::string& escenario,
    const std::string& rol          = "publisher",
    const std::string& security_dir = "security"
);

} // namespace security

#endif // SECURITY_CONFIG_H