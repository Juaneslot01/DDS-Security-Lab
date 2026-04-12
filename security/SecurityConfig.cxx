// =============================================================================
// SecurityConfig.cxx
//
// Implementación de la configuración de seguridad para FastDDS.
// Corregido para rutas absolutas en entornos Docker (file:///app/security).
//
// Compatible con: eProsima FastDDS 2.x
// Estándar:       OMG DDS Security v1.1
// =============================================================================

#include "SecurityConfig.h"

#include <fastrtps/rtps/common/Property.h>
#include <sys/stat.h>
#include <iostream>
#include <vector>
#include <stdexcept>
#include <string>
#include <thread>
#include <chrono>

namespace security {

// =============================================================================
// Funciones auxiliares privadas (Internal Linkage)
// =============================================================================

/**
 * Verifica la existencia física de un archivo en el sistema.
 */
static bool file_exists(const std::string& name) {
    struct stat buffer;
    return (stat(name.c_str(), &buffer) == 0);
}

/**
 * Construye un URI con esquema "file://" usando rutas ABSOLUTAS.
 * Crucial para que el motor de OpenSSL no confunda la ruta con un nombre de host.
 * Resultado esperado: file:///app/security/...
 */
static std::string make_file_uri(const std::string& base_dir, const std::string& filename) {
    // Aseguramos que la base_dir sea absoluta (empiece con /)
    std::string absolute_path = (base_dir[0] == '/') ? base_dir : "/" + base_dir;
    return "file://" + absolute_path + "/" + filename;
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

    // Lista de archivos según la estructura verificada por 'ls -R'
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

    // Ajuste de ruta para entorno Docker: Si recibe "security", lo convertimos en ruta absoluta
    std::string effective_dir = (security_dir == "security") ? "/app/security" : security_dir;

    // 2. Validación preventiva (Crucial para estabilidad en la Raspberry)
    if (!validate_artifacts(escenario, rol, effective_dir)) {
        throw std::runtime_error("❌ [Security Failure] Faltan artefactos en: " + effective_dir);
    }

    // 3. Preparación de rutas URI (file:///app/security/...)
    const std::string pki_dir    = effective_dir + "/pki";
    const std::string signed_dir = effective_dir + "/signed";
    const std::string perm_suffix = (rol == "publisher") ? "pub" : "sub";

    const std::string ca_cert     = make_file_uri(pki_dir, "maincacert.pem");
    const std::string node_cert   = make_file_uri(pki_dir, rol + "_cert.pem");
    const std::string node_key    = make_file_uri(pki_dir, rol + "_key.pem");
    const std::string governance  = make_file_uri(signed_dir, "gov_" + escenario + ".p7s");
    const std::string permissions = make_file_uri(signed_dir, "permissions_" + perm_suffix + ".p7s");

    // 4. Logging de diagnóstico
    std::cout << "🔒 [Security] Configurando Participante DDS:\n"
              << "   > Escenario: " << escenario << "\n"
              << "   > Rol:       " << rol << "\n"
              << "   > CA Path:   " << ca_cert << "\n"
              << "   > Gov Path:  " << governance << "\n";

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

    // 7. PLUGIN: Criptografía (AES-GCM-GMAC)
    // Requerido para TODOS los escenarios con seguridad activa, no solo encrypt/access.
    // El modo SIGN (usado en gov_auth.xml para discovery y liveliness) utiliza
    // AES-GCM-GMAC en modo GMAC puro (autenticación sin cifrado), pero el plugin
    // debe estar cargado para que FastDDS pueda firmar/verificar submensajes
    // HEARTBEAT y ACKNACK. Sin él la sesión crypto no se establece y el intercambio
    // de mensajes de control RTPS falla con "Cannot encrypt submessage".
    add_prop(pqos, "dds.sec.crypto.plugin", "builtin.AES-GCM-GMAC");
    if (escenario == "encrypt" || escenario == "access") {
        std::cout << "   > Cifrado:   Activado (AES-GCM-256)\n";
    } else {
        std::cout << "   > Cifrado:   GMAC-only (firma sin cifrado)\n";
    }

    std::cout << "✅ [Security] Plugins inyectados correctamente.\n\n";
}

} // namespace security
