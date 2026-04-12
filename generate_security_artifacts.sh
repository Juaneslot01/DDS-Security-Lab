#!/usr/bin/env bash
# ==============================================================================
#  generate_security_artifacts.sh
#  Generador de infraestructura PKI y S/MIME para el laboratorio DDS-Security.
#  Configurado para RSA-2048 para consistencia en mediciones de rendimiento.
# ==============================================================================

set -euo pipefail

# --- Colores para la documentación del proceso ---
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' CYAN='' YELLOW='' RED='' BOLD='' NC=''
fi

step() { echo -e "\n${BOLD}${CYAN}[PASO $1]${NC} $2"; }
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
fatal(){ echo -e "\n${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Rutas del Proyecto ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_DIR="${SCRIPT_DIR}/security"
PKI_DIR="${SECURITY_DIR}/pki"
SIGNED_DIR="${SECURITY_DIR}/signed"
XML_DIR="${SECURITY_DIR}/xml"

# --- 0. Verificaciones Previas ---
mkdir -p "${PKI_DIR}" "${SIGNED_DIR}"
command -v openssl >/dev/null 2>&1 || fatal "OpenSSL no instalado."

# Validar presencia de XMLs fuente
REQUIRED_XMLS=(gov_auth gov_encrypt gov_access permissions_pub permissions_sub)
for xml in "${REQUIRED_XMLS[@]}"; do
    [[ -f "${XML_DIR}/${xml}.xml" ]] || fatal "No se encontró ${xml}.xml en ${XML_DIR}"
done

# --- 1. Autoridad Certificadora (CA) ---
step "1/5" "Generando CA raíz (RSA-2048)..."
openssl req -nodes -x509 -days 3650 -newkey rsa:2048 \
    -keyout "${PKI_DIR}/ca_key.pem" \
    -out    "${PKI_DIR}/maincacert.pem" \
    -subj   "/C=CO/O=Uniandes/CN=Tesis-DDS-CA" 2>/dev/null
echo "01" > "${PKI_DIR}/ca_serial.txt"
ok "CA generada: maincacert.pem"

# --- 2 & 3. Certificados para Nodos (Publicador y Suscriptor) ---
for ROL in publisher subscriber; do
    CN_VAL=$( [[ "$ROL" == "publisher" ]] && echo "PayloadPublisher" || echo "PayloadSubscriber" )
    step "2-3/5" "Generando certificado para $ROL (RSA-2048)..."

    # Generar clave y CSR
    openssl req -nodes -newkey rsa:2048 \
        -keyout "${PKI_DIR}/${ROL}_key.pem" \
        -out    "${PKI_DIR}/${ROL}.csr" \
        -subj   "/C=CO/O=Uniandes/CN=${CN_VAL}" 2>/dev/null

    # Firmar con la CA
    openssl x509 -req -days 3650 \
        -in       "${PKI_DIR}/${ROL}.csr" \
        -CA       "${PKI_DIR}/maincacert.pem" \
        -CAkey    "${PKI_DIR}/ca_key.pem" \
        -CAserial "${PKI_DIR}/ca_serial.txt" \
        -out      "${PKI_DIR}/${ROL}_cert.pem" 2>/dev/null

    rm "${PKI_DIR}/${ROL}.csr"
    ok "$ROL: ${ROL}_cert.pem y ${ROL}_key.pem listos."
done

# --- 4. Firma de Gobernanza ---
step "4/5" "Firmando documentos de Gobernanza (S/MIME)..."
for GOV in gov_auth gov_encrypt gov_access; do
    openssl smime -sign -text \
        -in      "${XML_DIR}/${GOV}.xml" \
        -signer  "${PKI_DIR}/maincacert.pem" \
        -inkey   "${PKI_DIR}/ca_key.pem" \
        -out     "${SIGNED_DIR}/${GOV}.p7s" 2>/dev/null
    ok "${GOV}.p7s generado."
done

# --- 5. Firma de Permisos ---
step "5/5" "Firmando documentos de Permisos (S/MIME)..."
for PERM in permissions_pub permissions_sub; do
    openssl smime -sign -text \
        -in      "${XML_DIR}/${PERM}.xml" \
        -signer  "${PKI_DIR}/maincacert.pem" \
        -inkey   "${PKI_DIR}/ca_key.pem" \
        -out     "${SIGNED_DIR}/${PERM}.p7s" 2>/dev/null
    ok "${PERM}.p7s generado."
done

echo -e "\n${BOLD}${GREEN}✅ ¡Artefactos de seguridad sincronizados con el código C++ (RSA-2048)!${NC}\n"
