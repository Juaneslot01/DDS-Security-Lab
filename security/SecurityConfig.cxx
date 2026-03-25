// =============================================================================
// SecurityConfig.cxx
//
// Implementación de la función auxiliar configure_security_qos.
// Inyecta los plugins de seguridad DDS-Security (autenticación, control de
// acceso y cifrado) en el DomainParticipantQos de FastDDS.
//
// Compatible con: eProsima FastDDS 2.x (ROS 2 Humble / Ubuntu 22.04)
// Estándar:       OMG DDS Security v1.1
// =============================================================================

#include "security/SecurityConfig.h"

// PropertyPolicy y la clase Property viven en el namespace fastrtps::rtps
// aunque se accede a ellos a través del QoS del nivel DDS.
#include <fastrtps/rtps/common/PropertyPolicy.h>

#include <iostream>
#include <stdexcept>
#include <string>

namespace security {

// =============================================================================
// Funciones auxiliares de ámbito de archivo (no forman parte de la API pública)
// =============================================================================

// -----------------------------------------------------------------------------
// make_file_uri
// -----------------------------------------------------------------------------
// Construye un URI con esquema "file://" concatenando el directorio base y la
// ruta relativa. FastDDS usa este formato para localizar artefactos PKI en disco.
//
// Ejemplo:
//   make_file_uri("security/pki", "maincacert.pem")
//   → "file://security/pki/maincacert.pem"
//
// NOTA: La ruta resultante es relativa al CWD del proceso. El binario debe
//       ejecutarse desde la raíz del proyecto (p. ej.: /app en el contenedor).
// -----------------------------------------------------------------------------
static std::string make_file_uri(const std::string& base_dir,
                                 const std::string& filename)
{
    return "file://" + base_dir + "/" + filename;
}

// -----------------------------------------------------------------------------
// add_prop
// -----------------------------------------------------------------------------
// Añade una propiedad nombre=valor a la PropertyPolicy del QoS del participante.
// Internamente, DomainParticipantQos::properties() devuelve una referencia a
// eprosima::fastrtps::rtps::PropertyPolicy, cuyo vector de Property se expande
// aquí con emplace_back usando el constructor Property(name, value).
// -----------------------------------------------------------------------------
static void add_prop(eprosima::fastdds::dds::DomainParticipantQos& pqos,
                     const std::string& name,
                     const std::string& value)
{
    pqos.properties().properties().emplace_back(name, value);
}

// =============================================================================
// configure_security_qos  —  Implementación pública
// =============================================================================
void configure_security_qos(
        eprosima::fastdds::dds::DomainParticipantQos& pqos,
        const std::string& escenario,
        const std::string& rol,
        const std::string& security_dir)
{
    // -------------------------------------------------------------------------
    // Escenario "none": sin seguridad.
    // Retorna inmediatamente sin tocar el QoS. Permite usar el mismo binario
    // como línea base no segura en los experimentos de rendimiento.
    // -------------------------------------------------------------------------
    if (escenario == "none")
    {
        std::cout << "[Security] Escenario 'none': "
                  << "el participante arranca SIN seguridad DDS.\n";
        return;
    }

    // -------------------------------------------------------------------------
    // Validación del parámetro 'escenario'
    // -------------------------------------------------------------------------
    if (escenario != "auth" && escenario != "encrypt" && escenario != "access")
    {
        throw std::invalid_argument(
            std::string("[Security] Escenario desconocido: '") + escenario +
            "'. Valores válidos: none | auth | encrypt | access");
    }

    // -------------------------------------------------------------------------
    // Validación del parámetro 'rol'
    // -------------------------------------------------------------------------
    if (rol != "publisher" && rol != "subscriber")
    {
        throw std::invalid_argument(
            std::string("[Security] Rol desconocido: '") + rol +
            "'. Valores válidos: publisher | subscriber");
    }

    // -------------------------------------------------------------------------
    // Construcción de rutas a los artefactos de seguridad
    // -------------------------------------------------------------------------
    // Subdirectorio PKI: contiene la CA y los certificados/claves de cada nodo.
    const std::string pki_dir    = security_dir + "/pki";

    // Subdirectorio Signed: contiene los documentos XML firmados (.p7s).
    const std::string signed_dir = security_dir + "/signed";

    // ── CA ────────────────────────────────────────────────────────────────────
    // Un único certificado de CA sirve tanto como identity_ca (para el plugin
    // de autenticación PKI-DH) como permissions_ca (para el plugin de acceso).
    const std::string ca_cert = make_file_uri(pki_dir, "maincacert.pem");

    // ── Identidad del nodo ────────────────────────────────────────────────────
    // El nombre del archivo se construye dinámicamente según el rol:
    //   publisher  → publisher_cert.pem  /  publisher_key.pem
    //   subscriber → subscriber_cert.pem /  subscriber_key.pem
    const std::string node_cert = make_file_uri(pki_dir, rol + "_cert.pem");
    const std::string node_key  = make_file_uri(pki_dir, rol + "_key.pem");

    // ── Gobernanza firmada ─────────────────────────────────────────────────────
    // El archivo de gobernanza define la política del dominio:
    //   auth    → gov_auth.p7s    (sin cifrado, con autenticación)
    //   encrypt → gov_encrypt.p7s (cifrado AES-GCM total, sin ctrl de tópicos)
    //   access  → gov_access.p7s  (cifrado AES-GCM + control de acceso por tópico)
    const std::string governance = make_file_uri(signed_dir,
                                                 "gov_" + escenario + ".p7s");

    // ── Permisos firmados del participante ────────────────────────────────────
    // Cada participante carga SUS propios permisos. La CA los firma para
    // garantizar su autenticidad e integridad.
    //   publisher  → permissions_pub.p7s  (puede publicar en payloadTopic)
    //   subscriber → permissions_sub.p7s  (puede suscribirse a payloadTopic)
    const std::string perm_suffix  = (rol == "publisher") ? "pub" : "sub";
    const std::string permissions  = make_file_uri(signed_dir,
                                                   "permissions_" + perm_suffix + ".p7s");

    // ─────────────────────────────────────────────────────────────────────────
    // Diagnóstico: mostrar la configuración que se va a aplicar
    // ─────────────────────────────────────────────────────────────────────────
    std::cout << "\n[Security] ══════════════════════════════════════════════\n"
              << "[Security]  Escenario : " << escenario << "\n"
              << "[Security]  Rol       : " << rol       << "\n"
              << "[Security] ──────────────────────────────────────────────\n"
              << "[Security]  CA cert   : " << ca_cert     << "\n"
              << "[Security]  Nodo cert : " << node_cert   << "\n"
              << "[Security]  Nodo key  : " << node_key    << "\n"
              << "[Security]  Governance: " << governance  << "\n"
              << "[Security]  Permisos  : " << permissions << "\n"
              << "[Security] ══════════════════════════════════════════════\n\n";


    // =========================================================================
    // PLUGIN 1: dds.sec.auth.plugin → builtin.PKI-DH
    // =========================================================================
    // El plugin PKI-DH implementa el protocolo de autenticación definido en
    // DDS Security v1.1 §8.3. El flujo es el siguiente:
    //
    //   1. Al arrancar, el participante local carga su certificado X.509
    //      (identity_certificate) y verifica que fue firmado por la CA
    //      configurada en identity_ca.
    //
    //   2. Cuando descubre a otro participante remoto, intercambia con él un
    //      handshake de 3 mensajes (RequestHandshake / ReplyHandshake /
    //      FinalizeHandshake) que:
    //        a) Autentica el certificado del remoto contra la misma CA.
    //        b) Negocia material criptográfico compartido mediante ECDH
    //           (Elliptic-Curve Diffie-Hellman) para derivar claves de sesión.
    //
    //   3. Solo si ambos participantes superan la autenticación se establece
    //      el canal DDS entre ellos.
    // =========================================================================

    // Activar el plugin de autenticación
    add_prop(pqos,
             "dds.sec.auth.plugin",
             "builtin.PKI-DH");

    // CA raíz de confianza. El certificado de cualquier participante remoto
    // debe haber sido firmado por esta CA para ser aceptado.
    add_prop(pqos,
             "dds.sec.auth.builtin.PKI-DH.identity_ca",
             ca_cert);

    // Certificado X.509 de ESTE participante.
    // El remoto lo verificará contra la CA para autenticarnos.
    add_prop(pqos,
             "dds.sec.auth.builtin.PKI-DH.identity_certificate",
             node_cert);

    // Clave privada RSA/ECDSA de ESTE participante.
    // Se usa para firmar el handshake DH y demostrar posesión del certificado.
    add_prop(pqos,
             "dds.sec.auth.builtin.PKI-DH.private_key",
             node_key);


    // =========================================================================
    // PLUGIN 2: dds.sec.access.plugin → builtin.Access-Permissions
    // =========================================================================
    // El plugin Access-Permissions implementa el control de acceso definido en
    // DDS Security v1.1 §8.4. Evalúa dos tipos de documentos firmados (S/MIME):
    //
    //   • Governance (.p7s): política global del dominio.
    //     Indica qué protecciones se aplican y si el acceso a tópicos se
    //     controla (enable_join_access_control, enable_read/write_access_control,
    //     rtps_protection_kind, data_protection_kind, etc.).
    //
    //   • Permissions (.p7s): permisos individuales de ESTE participante.
    //     Indica a qué dominios puede unirse, qué tópicos puede publicar y
    //     en qué tópicos puede suscribirse.
    //
    // El plugin verifica la firma de ambos documentos contra permissions_ca.
    // Si la firma no es válida o el participante no tiene permiso para la
    // operación solicitada, FastDDS bloquea la operación.
    //
    // Cuándo se evalúa cada comprobación:
    //   · JOIN al dominio  → siempre, si enable_join_access_control=true.
    //   · PUBLICAR tópico  → solo si enable_write_access_control=true (gov).
    //   · SUSCRIBIR tópico → solo si enable_read_access_control=true  (gov).
    // =========================================================================

    // Activar el plugin de control de acceso
    add_prop(pqos,
             "dds.sec.access.plugin",
             "builtin.Access-Permissions");

    // CA que firmó los documentos de gobernanza y permisos.
    // El plugin verifica la firma CMS de los .p7s contra este certificado.
    // En este proyecto usamos la misma CA para autenticación y permisos.
    add_prop(pqos,
             "dds.sec.access.builtin.Access-Permissions.permissions_ca",
             ca_cert);

    // Documento de gobernanza firmado correspondiente al escenario.
    // Define la política del dominio completo (qué se cifra, qué se controla).
    // Todos los participantes del mismo dominio deben usar la MISMA gobernanza.
    add_prop(pqos,
             "dds.sec.access.builtin.Access-Permissions.governance",
             governance);

    // Documento de permisos firmado específico de ESTE participante.
    // Define qué tópicos puede publicar/suscribir y en qué dominio.
    // publisher usa permissions_pub.p7s; subscriber usa permissions_sub.p7s.
    add_prop(pqos,
             "dds.sec.access.builtin.Access-Permissions.permissions",
             permissions);


    // =========================================================================
    // PLUGIN 3: dds.sec.crypto.plugin → builtin.AES-GCM-GMAC
    // =========================================================================
    // El plugin criptográfico implementa el cifrado y autenticación de mensajes
    // definido en DDS Security v1.1 §8.5. Utiliza:
    //
    //   • AES-GCM (Galois/Counter Mode): cifrado autenticado (AEAD) con
    //     claves de 128 o 256 bits. Proporciona confidencialidad + integridad
    //     en una sola pasada.
    //
    //   • AES-GMAC: variante que solo firma (GMAC tag) sin cifrar. Usada
    //     cuando data_protection_kind=SIGN en la gobernanza.
    //
    // El plugin se activa aquí explícitamente para los escenarios "encrypt" y
    // "access", que son los únicos que configuran protection_kind != NONE en la
    // gobernanza. Para "auth", el plugin no es necesario porque la gobernanza
    // fija NONE para todos los tipos de protección de datos.
    //
    // Las claves de sesión se derivan del material compartido negociado durante
    // el handshake PKI-DH; se rotan automáticamente por FastDDS.
    // =========================================================================

    if (escenario == "encrypt" || escenario == "access")
    {
        add_prop(pqos,
                 "dds.sec.crypto.plugin",
                 "builtin.AES-GCM-GMAC");
    }

    std::cout << "[Security] Plugins de seguridad configurados correctamente.\n"
              << "[Security] El participante usará escenario='"
              << escenario << "'.\n\n";
}

} // namespace security