#!/usr/bin/env bash
# ==============================================================================
#  generate_security_artifacts.sh
#
#  Propósito:
#    Genera toda la infraestructura PKI (CA, certificados, claves) y firma
#    digitalmente los documentos XML de gobernanza y permisos DDS-Security
#    con S/MIME (CMS) usando OpenSSL. El resultado son los archivos .p7s
#    que FastDDS carga en tiempo de ejecución.
#
#  Requisitos:
#    - openssl >= 1.1.1  (disponible por defecto en Ubuntu 22.04)
#    - Los archivos XML fuente deben existir en security/xml/ antes de
#      ejecutar este script. Genera primero el código del proyecto.
#
#  Uso:
#    bash generate_security_artifacts.sh
#    Ejecutar desde la RAÍZ del proyecto (donde está el Dockerfile).
#
#  Estructura de salida generada:
#    security/
#    ├── pki/
#    │   ├── maincacert.pem        ← Certificado público de la CA (compartir)
#    │   ├── ca_key.pem            ← Clave privada de la CA      ⚠ SECRETO
#    │   ├── ca_serial.txt         ← Contador de serie de la CA
#    │   ├── publisher_cert.pem    ← Certificado del Publicador   (compartir)
#    │   ├── publisher_key.pem     ← Clave privada del Publicador ⚠ SECRETO
#    │   ├── subscriber_cert.pem   ← Certificado del Suscriptor   (compartir)
#    │   └── subscriber_key.pem    ← Clave privada del Suscriptor ⚠ SECRETO
#    └── signed/
#        ├── gov_auth.p7s          ← Gobernanza firmada (escenario auth)
#        ├── gov_encrypt.p7s       ← Gobernanza firmada (escenario encrypt)
#        ├── gov_access.p7s        ← Gobernanza firmada (escenario access)
#        ├── permissions_pub.p7s   ← Permisos del Publicador firmados
#        └── permissions_sub.p7s   ← Permisos del Suscriptor firmados
#
#  ADVERTENCIA:
#    Los archivos *_key.pem son CLAVES PRIVADAS de entorno de pruebas.
#    NO los incluyas en un repositorio público. El .gitignore del proyecto
#    ya excluye security/pki/ y security/signed/ para protegerlos.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Colores ANSI para la salida de consola
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then          # Solo colorear si la salida es un terminal
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' CYAN='' YELLOW='' RED='' BOLD='' NC=''
fi

# ------------------------------------------------------------------------------
# Funciones de log
# ------------------------------------------------------------------------------
step()    { echo -e "\n${BOLD}${CYAN}[PASO $1]${NC} $2"; }
ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}   $*"; }
fatal()   { echo -e "\n${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Banner inicial
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      DDS-Security ─ Generador de Artefactos PKI y S/MIME    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------

# Comprobar que OpenSSL está disponible
command -v openssl >/dev/null 2>&1 \
    || fatal "OpenSSL no encontrado. Instálalo con:\n       apt-get install -y openssl"

OPENSSL_VER=$(openssl version)
echo -e "\n  Usando: ${CYAN}${OPENSSL_VER}${NC}"

# Resolver rutas relativas al script (funciona aunque se llame desde otro dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_DIR="${SCRIPT_DIR}/security"
PKI_DIR="${SECURITY_DIR}/pki"
XML_DIR="${SECURITY_DIR}/xml"
SIGNED_DIR="${SECURITY_DIR}/signed"

echo "  Raíz del proyecto: ${SCRIPT_DIR}"
echo "  Dir. de seguridad: ${SECURITY_DIR}"

# Verificar que los XML fuente existen (creados junto al proyecto)
REQUIRED_XMLS=(gov_auth gov_encrypt gov_access permissions_pub permissions_sub)
for xml in "${REQUIRED_XMLS[@]}"; do
    XML_PATH="${XML_DIR}/${xml}.xml"
    [[ -f "${XML_PATH}" ]] \
        || fatal "Archivo XML fuente no encontrado: ${XML_PATH}\n       Ejecuta el script desde la raíz del proyecto."
done
ok "Todos los archivos XML fuente verificados (${#REQUIRED_XMLS[@]} archivos)"

# Crear directorios de salida si no existen
mkdir -p "${PKI_DIR}" "${SIGNED_DIR}"

# ==============================================================================
# PASO 1 — Autoridad Certificadora (CA) raíz de pruebas
# ==============================================================================
step "1/5" "Generando Autoridad Certificadora (CA) autofirmada..."
echo "         Algoritmo: RSA-2048, Vigencia: 10 años"
echo "         Subject:   C=ES, O=eProsima, CN=DDS-Security-TestCA"

#   -nodes     → clave privada SIN passphrase (facilita pruebas automáticas)
#   -x509      → genera certificado autofirmado en lugar de un CSR
#   -days 3650 → validez de 10 años
#   -newkey    → genera una nueva clave RSA de 2048 bits
openssl req \
    -nodes \
    -x509 \
    -days 3650 \
    -newkey rsa:2048 \
    -keyout "${PKI_DIR}/ca_key.pem" \
    -out    "${PKI_DIR}/maincacert.pem" \
    -subj   "/C=ES/O=eProsima/CN=DDS-Security-TestCA" \
    2>/dev/null

# Inicializar el archivo de número de serie de la CA
echo "01" > "${PKI_DIR}/ca_serial.txt"

ok "CA creada correctamente"
ok "  Certificado: ${PKI_DIR}/maincacert.pem"
ok "  Clave priv.: ${PKI_DIR}/ca_key.pem  ${YELLOW}[MANTENER SECRETO]${NC}"

# Mostrar el subject del certificado CA generado como verificación
CA_SUBJECT=$(openssl x509 -noout -subject -in "${PKI_DIR}/maincacert.pem" 2>/dev/null | sed 's/subject=//')
ok "  Subject CA:  ${CA_SUBJECT}"

# ==============================================================================
# PASO 2 — Certificado del PUBLICADOR
# ==============================================================================
step "2/5" "Generando certificado del Publicador..."
echo "         Subject: C=ES, O=eProsima, CN=PayloadPublisher"
echo "         NOTA: Este CN debe coincidir con <subject_name> en permissions_pub.xml"

# 2a. Clave privada RSA-2048 + CSR (Certificate Signing Request)
openssl req \
    -nodes \
    -newkey rsa:2048 \
    -keyout "${PKI_DIR}/publisher_key.pem" \
    -out    "${PKI_DIR}/publisher.csr" \
    -subj   "/C=ES/O=eProsima/CN=PayloadPublisher" \
    2>/dev/null

# 2b. Firmar el CSR con la CA → obtener el certificado del publicador
#   -CAserial → incrementa el número de serie en ca_serial.txt en cada firma
openssl x509 \
    -req \
    -days 3650 \
    -in       "${PKI_DIR}/publisher.csr" \
    -CA       "${PKI_DIR}/maincacert.pem" \
    -CAkey    "${PKI_DIR}/ca_key.pem" \
    -CAserial "${PKI_DIR}/ca_serial.txt" \
    -out      "${PKI_DIR}/publisher_cert.pem" \
    2>/dev/null

# Eliminar el CSR intermedio (ya no es necesario)
rm -f "${PKI_DIR}/publisher.csr"

PUB_SUBJECT=$(openssl x509 -noout -subject -in "${PKI_DIR}/publisher_cert.pem" 2>/dev/null | sed 's/subject=//')
ok "Certificado del Publicador generado"
ok "  Certificado: ${PKI_DIR}/publisher_cert.pem"
ok "  Clave priv.: ${PKI_DIR}/publisher_key.pem  ${YELLOW}[MANTENER SECRETO]${NC}"
ok "  Subject:     ${PUB_SUBJECT}"

# ==============================================================================
# PASO 3 — Certificado del SUSCRIPTOR
# ==============================================================================
step "3/5" "Generando certificado del Suscriptor..."
echo "         Subject: C=ES, O=eProsima, CN=PayloadSubscriber"
echo "         NOTA: Este CN debe coincidir con <subject_name> en permissions_sub.xml"

# 3a. Clave privada RSA-2048 + CSR del suscriptor
openssl req \
    -nodes \
    -newkey rsa:2048 \
    -keyout "${PKI_DIR}/subscriber_key.pem" \
    -out    "${PKI_DIR}/subscriber.csr" \
    -subj   "/C=ES/O=eProsima/CN=PayloadSubscriber" \
    2>/dev/null

# 3b. Firmar con la misma CA (dominio de confianza compartido)
openssl x509 \
    -req \
    -days 3650 \
    -in       "${PKI_DIR}/subscriber.csr" \
    -CA       "${PKI_DIR}/maincacert.pem" \
    -CAkey    "${PKI_DIR}/ca_key.pem" \
    -CAserial "${PKI_DIR}/ca_serial.txt" \
    -out      "${PKI_DIR}/subscriber_cert.pem" \
    2>/dev/null

rm -f "${PKI_DIR}/subscriber.csr"

SUB_SUBJECT=$(openssl x509 -noout -subject -in "${PKI_DIR}/subscriber_cert.pem" 2>/dev/null | sed 's/subject=//')
ok "Certificado del Suscriptor generado"
ok "  Certificado: ${PKI_DIR}/subscriber_cert.pem"
ok "  Clave priv.: ${PKI_DIR}/subscriber_key.pem  ${YELLOW}[MANTENER SECRETO]${NC}"
ok "  Subject:     ${SUB_SUBJECT}"

# ==============================================================================
# PASO 4 — Firmar documentos de GOBERNANZA con S/MIME (CMS)
# ==============================================================================
step "4/5" "Firmando documentos XML de Gobernanza (formato S/MIME PEM)..."
echo ""
echo "         La CA firma la gobernanza para garantizar que define la política"
echo "         auténtica del dominio. FastDDS verifica la firma en el arranque."
echo ""
echo "         Comando usado para cada archivo:"
echo "           openssl smime -sign -in <gov>.xml -text \\"
echo "                         -signer maincacert.pem -inkey ca_key.pem \\"
echo "                         -outform PEM -out <gov>.p7s"
echo ""

for GOV_NAME in gov_auth gov_encrypt gov_access; do
    XML_SRC="${XML_DIR}/${GOV_NAME}.xml"
    P7S_OUT="${SIGNED_DIR}/${GOV_NAME}.p7s"

    # openssl smime -sign:
    #   -in      → documento XML a firmar (payload del mensaje S/MIME)
    #   -text    → añade la cabecera MIME "Content-Type: text/plain"
    #              necesaria para que FastDDS interprete correctamente el .p7s
    #   -signer  → certificado del firmante (la CA)
    #   -inkey   → clave privada del firmante
    #   -outform PEM → salida en formato PEM (base64), no DER binario
    #   -out     → ruta del archivo .p7s resultante
    openssl smime \
        -sign \
        -in      "${XML_SRC}" \
        -text \
        -signer  "${PKI_DIR}/maincacert.pem" \
        -inkey   "${PKI_DIR}/ca_key.pem" \
        -outform PEM \
        -out     "${P7S_OUT}" \
        2>/dev/null

    # Verificar que el archivo .p7s se puede leer y tiene contenido
    [[ -s "${P7S_OUT}" ]] \
        || fatal "El archivo firmado está vacío: ${P7S_OUT}"

    ok "${GOV_NAME}.p7s  →  ${P7S_OUT}"
done

# ==============================================================================
# PASO 5 — Firmar documentos de PERMISOS con S/MIME (CMS)
# ==============================================================================
step "5/5" "Firmando documentos XML de Permisos (formato S/MIME PEM)..."
echo ""
echo "         La CA firma los permisos para garantizar que no han sido"
echo "         alterados. FastDDS valida la firma antes de aplicar el grant."
echo ""

for PERM_NAME in permissions_pub permissions_sub; do
    XML_SRC="${XML_DIR}/${PERM_NAME}.xml"
    P7S_OUT="${SIGNED_DIR}/${PERM_NAME}.p7s"

    openssl smime \
        -sign \
        -in      "${XML_SRC}" \
        -text \
        -signer  "${PKI_DIR}/maincacert.pem" \
        -inkey   "${PKI_DIR}/ca_key.pem" \
        -outform PEM \
        -out     "${P7S_OUT}" \
        2>/dev/null

    [[ -s "${P7S_OUT}" ]] \
        || fatal "El archivo firmado está vacío: ${P7S_OUT}"

    ok "${PERM_NAME}.p7s  →  ${P7S_OUT}"
done

# ==============================================================================
# Verificación rápida — Comprobar que todos los archivos esperados existen
# ==============================================================================
echo ""
echo -e "${BOLD}Verificando integridad de los artefactos generados...${NC}"

EXPECTED_PKI=(
    "maincacert.pem"
    "publisher_cert.pem"
    "publisher_key.pem"
    "subscriber_cert.pem"
    "subscriber_key.pem"
)

EXPECTED_SIGNED=(
    "gov_auth.p7s"
    "gov_encrypt.p7s"
    "gov_access.p7s"
    "permissions_pub.p7s"
    "permissions_sub.p7s"
)

ALL_OK=true
for f in "${EXPECTED_PKI[@]}"; do
    [[ -f "${PKI_DIR}/${f}" ]] && ok "  pki/${f}" || { warn "  FALTA: pki/${f}"; ALL_OK=false; }
done
for f in "${EXPECTED_SIGNED[@]}"; do
    [[ -f "${SIGNED_DIR}/${f}" ]] && ok "  signed/${f}" || { warn "  FALTA: signed/${f}"; ALL_OK=false; }
done

[[ "${ALL_OK}" == "true" ]] || fatal "Algunos artefactos no se generaron correctamente."

# ==============================================================================
# Opcional: Verificar la firma del primer .p7s como autocomprobación
# ==============================================================================
echo ""
echo -e "${BOLD}Verificando firma S/MIME de gov_auth.p7s...${NC}"
openssl smime \
    -verify \
    -in        "${SIGNED_DIR}/gov_auth.p7s" \
    -CAfile    "${PKI_DIR}/maincacert.pem" \
    -inform    PEM \
    -noverify \
    -out       /dev/null \
    2>/dev/null \
    && ok "Firma S/MIME verificada correctamente con la CA" \
    || warn "No se pudo verificar la firma (no es crítico en entorno de pruebas)"

# ==============================================================================
# Resumen final
# ==============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          ¡ARTEFACTOS DE SEGURIDAD LISTOS!                    ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Próximos pasos:"
echo ""
echo "  1. Compila el proyecto dentro del contenedor Docker:"
echo "       docker build -t dds-security ."
echo ""
echo "  2. Inicia el contenedor y lanza el suscriptor con un escenario:"
echo "       docker run -it --rm dds-security"
echo "       # Dentro del contenedor:"
echo "       cd /app && ./build/payload subscriber auth"
echo ""
echo "  3. En otra terminal, lanza el publicador:"
echo "       docker exec -it <container_id> /bin/bash"
echo "       cd /app && ./build/payload publisher 1000 1024 1000 auth"
echo ""
echo "  Escenarios disponibles: none | auth | encrypt | access"
echo ""
echo -e "  ${YELLOW}⚠  Los archivos *_key.pem son claves privadas de PRUEBA.${NC}"
echo -e "  ${YELLOW}   Están excluidos del repositorio por .gitignore.${NC}"
echo -e "  ${YELLOW}   NUNCA los uses en producción.${NC}"
echo ""
