#!/bin/bash

# Redirigir toda la salida a un archivo con marca de tiempo y a la terminal simultáneamente
LOG_FILE="benchmark_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1
# run_benchmarks.sh - Ejecutar en CachyOS (PC)

# ==========================================
# VALIDACIONES CRÍTICAS DE DEPENDENCIAS
# ==========================================
command -v docker >/dev/null 2>&1 || { echo "❌ Error: Docker no está instalado en este PC."; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "❌ Error: SSH no está instalado en este PC."; exit 1; }

# --- CONFIGURACIÓN ---
PI_USER="pi"
PI_IP="192.168.20.53"
DIR_PI="/home/pi/dds-security-lab"   # Ruta del proyecto en la Pi
DIR_PC=$(pwd)                        # Ruta actual en CachyOS

ESCENARIOS=("none" "auth" "encrypt" "access")
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000 # 1000 de calentamiento + 10000 de medición

# ==========================================
# VALIDACIÓN CRÍTICA DE CONEXIÓN
# ==========================================
echo "🔍 Verificando conexión con la Raspberry Pi en ${PI_IP}..."
# Intentar conexión rápida (5 segundos de timeout) para no quedarse colgado
ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${PI_USER}@${PI_IP} exit || { echo "❌ Error: No se puede conectar a la Raspberry Pi. Revisa que esté encendida y en la misma red."; exit 1; }
echo "✅ Conexión con la Raspberry Pi exitosa."
echo "------------------------------------------------------"

# Crear carpetas de resultados
mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🚀 Iniciando orquestación de pruebas DDS-Security..."

for escenario in "${ESCENARIOS[@]}"; do
    for payload in "${PAYLOADS[@]}"; do

        echo "======================================================"
        echo "⚙️ Escenario: [$escenario] | Payload: [$payload Bytes]"
        echo "======================================================"

        for ((i=1; i<=CORRIDAS; i++)); do
            echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

            CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${escenario}_${payload}B_run${i}.csv"
            CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${escenario}_${payload}B_run${i}.csv"

            # 1. Arrancar Suscriptor en el PC con timeout de 5 minutos
            timeout 300 docker run --rm --net=host --ipc=host \
                dds-lab ./build/payload subscriber ${escenario} > ${CSV_LATENCIA} &
            SUB_PID=$!

            sleep 2 # Dar tiempo a que el Suscriptor esté escuchando

            # 2. Arrancar el Monitor de Recursos en la Pi
            ssh ${PI_USER}@${PI_IP} "nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!" > monitor.pid

            # 3. Arrancar Publicador en la Pi con timeout de 5 minutos
            ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --net=host --ipc=host dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${escenario}" || echo "⚠️ Alerta: Timeout o error en el nodo publicador."

            # 4. Detener el Monitor de Recursos en la Pi
            PID_MONITOR=$(cat monitor.pid)
            ssh ${PI_USER}@${PI_IP} "kill $PID_MONITOR"
            rm monitor.pid

            # 5. Esperar a que el contenedor del Suscriptor local termine
            wait $SUB_PID

            # 6. Enfriamiento para evitar Thermal Throttling
            echo "❄️ Corrida $i terminada. Enfriando por 10 segundos..."
            sleep 10
        done
    done
done

echo "✅ ¡Todas las pruebas finalizaron con éxito!"
