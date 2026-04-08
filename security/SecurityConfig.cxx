// =============================================================================
// SecurityConfig.cxx
//
// Implementación de la configuración de seguridad para FastDDS.
// Incluye validación preventiva de artefactos para evitar fallos de segmentación.
//
// Compatible con: eProsima FastDDS 2.x
// Estándar:       OMG DDS Security v1.1
// =============================================================================

#include "SecurityConfig.h"

#include <fastrtps/rtps/common/PropertyPolicy.h>
#include <sys/stat.h>
#include <iostream>
#include <vector>
#include <stdexcept>
#include <string>

namespace security {

// =============================================================================
// Funciones auxiliares privadas (Internal Linkage)
// =============================================================================

/**
 * Verifica la existencia física de un archivo en el sistema.
 * Evita que FastDDS intente cargar punteros nulos al no encontrar certificados.
 */
static bool file_exists(const std::string& name) {
    struct stat buffer;
    return (stat(name.c_str(), &buffer) == 0);
}

/**
 * Construye un URI con esquema "file://" compatible con el parser de FastDDS.
 */
static std::string make_file_uri(const std::string& base_dir, const std::string& filename) {
    return "file://" + base_dir + "/" + filename;
}

/**
 * Inyecta una propiedad en la política del QoS del participante.
 */
static void add_prop(eprosima::fastdds::dds::DomainParticipantQos& pqos,
                     const std::string& name,
                     const std::string& value) {
    pqos.properties().properties().emplace_back(name, value);
}

// =============================================================================
// Implementación de la API Pública
// =============================================================================

bool validate_artifacts(const std::string& escenario,
                        const std::string& rol,
                        const std::string& security_dir)
{
    if (escenario == "none") return true;

    const std::string pki_dir = security_dir + "/pki";
    const std::string signed_dir = security_dir + "/signed";
    const std::string perm_suffix = (rol == "publisher") ? "pub" : "sub";

    // Lista de archivos que DEBEN existir para que el escenario sea válido
    std::vector<std::string> critical_files = {
        pki_dir + "/maincacert.pem",
        pki_dir + "/" + rol + "_cert.pem",
        pki_dir + "/" + rol + "_key.pem",
        signed_dir + "/gov_" + escenario + ".p7s",
        signed_dir + "/permissions_" + perm_suffix + ".p7s"
    };

    bool all_present = true;
    for (const auto& file : critical_files) {
        if (!file_exists(file)) {
            std::cerr << "❌ [Security Error] Archivo no encontrado: " << file << std::endl;
            all_present = false;
        }
    }

    return all_present;
}

void configure_security_qos(eprosima::fastdds::dds::DomainParticipantQos& pqos,
                            const std::string& escenario,
                            const std::string& rol,
                            const std::string& security_dir)
{
    // 1. Caso base: Sin seguridad
    if (escenario == "none") {
        std::cout << "ℹ️ [Security] Escenario 'none': Iniciando sin plugins de seguridad.\n";
        return;
    }

    // 2. Validación preventiva (Crucial para estabilidad en Docker/Raspberry)
    if (!validate_artifacts(escenario, rol, security_dir)) {
        throw std::runtime_error("❌ [Security Failure] Faltan artefactos criptográficos necesarios.");
    }

    // 3. Preparación de rutas URI
    const std::string pki_dir    = security_dir + "/pki";
    const std::string signed_dir = security_dir + "/signed";
    const std::string perm_suffix = (rol == "publisher") ? "pub" : "sub";

    const std::string ca_cert     = make_file_uri(pki_dir, "maincacert.pem");
    const std::string node_cert   = make_file_uri(pki_dir, rol + "_cert.pem");
    const std::string node_key    = make_file_uri(pki_dir, rol + "_key.pem");
    const std::string governance  = make_file_uri(signed_dir, "gov_" + escenario + ".p7s");
    const std::string permissions = make_file_uri(signed_dir, "permissions_" + perm_suffix + ".p7s");

    // 4. Logging de diagnóstico (útil para auditoría de la tesis)
    std::cout << "🔒 [Security] Configurando Participante DDS:\n"
              << "   > Escenario: " << escenario << "\n"
              << "   > Rol:       " << rol << "\n"
              << "   > CA:        " << ca_cert << "\n";

    // 5. PLUGIN: Autenticación (PKI-DH)
    add_prop(pqos, "dds.sec.auth.plugin", "builtin.PKI-DH");
    add_prop(pqos, "dds.sec.auth.builtin.PKI-DH.identity_ca", ca_cert);
    add_prop(pqos, "dds.sec.auth.builtin.PKI-DH.identity_certificate", node_cert);
    add_prop(pqos, "dds.sec.auth.builtin.PKI-DH.private_key", node_key);

    // 6. PLUGIN: Control de Acceso
    add_prop(pqos, "dds.sec.access.plugin", "builtin.Access-Permissions");
    add_prop(pqos, "dds.sec.access.builtin.Access-Permissions.permissions_ca", ca_cert);
    add_prop(pqos, "dds.sec.access.builtin.Access-Permissions.governance", governance);
    add_prop(pqos, "dds.sec.access.builtin.Access-Permissions.permissions", permissions);

    // 7. PLUGIN: Criptografía (Solo si el escenario lo requiere)
    if (escenario == "encrypt" || escenario == "access") {
        add_prop(pqos, "dds.sec.crypto.plugin", "builtin.AES-GCM-GMAC");
        std::cout << "   > Cifrado:   Activado (AES-GCM-256)\n";
    }

    std::cout << "✅ [Security] Plugins inyectados correctamente.\n\n";
}

} // namespace security
