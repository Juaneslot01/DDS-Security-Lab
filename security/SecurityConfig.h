#ifndef SECURITY_CONFIG_H
#define SECURITY_CONFIG_H

#include <fastdds/dds/domain/qos/DomainParticipantQos.hpp>
#include <string>

namespace security {

/**
 * Valida la existencia de archivos .pem y .p7s.
 */
bool validate_artifacts(
    const std::string& escenario,
    const std::string& rol,
    const std::string& security_dir = "security");

/**
 * Configura los plugins de seguridad en el QoS del participante.
 */
void configure_security_qos(
    eprosima::fastdds::dds::DomainParticipantQos& pqos,
    const std::string& escenario,
    const std::string& rol,
    const std::string& security_dir = "security");

} // namespace security

#endif
