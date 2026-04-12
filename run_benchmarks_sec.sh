#!/bin/bash

# Redirigir toda la salida a un archivo con marca de tiempo y a la terminal
LOG_FILE="benchmark_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# --- CONFIGURACIÓN ---
PI_USER="pi"
PI_IP="192.168.20.49"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

# Saltamos "none" para ahorrar tiempo
ESCENARIOS=("auth" "encrypt" "access")
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000

echo "🔍 Verificando conexión con la Raspberry Pi en ${PI_IP}..."
ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${PI_USER}@${PI_IP} exit || { echo "❌ Error: No se puede conectar a la Pi."; exit 1; }
echo "✅ Conexión exitosa."

mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🚀 Iniciando orquestación (Escenarios de Seguridad)..."

for escenario in "${ESCENARIOS[@]}"; do
    for payload in "${PAYLOADS[@]}"; do

        echo "======================================================"
        echo "⚙️ Escenario: [$escenario] | Payload: [$payload Bytes]"
        echo "======================================================"

        for ((i=1; i<=CORRIDAS; i++)); do
            echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

            CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${escenario}_${payload}B_run${i}.csv"
            CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${escenario}_${payload}B_run${i}.csv"

            # 1. Arrancar Suscriptor en el PC (-w /app es la clave para los certificados)
            timeout 300 docker run --rm --net=host --ipc=host -w /app \
                dds-lab ./build/payload subscriber ${escenario} > ${CSV_LATENCIA} &
            SUB_PID=$!

            sleep 2

            # 2. Limpieza preventiva y Monitor en la Pi
            ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher 2>/dev/null || true"
            ssh ${PI_USER}@${PI_IP} "nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!" > monitor.pid

            # 3. Arrancar Publicador en la Pi (-w /app agregado aquí también)
            ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${escenario}" || echo "⚠️ Alerta: Timeout o error en el nodo publicador."

            # 4. Detener el Monitor
            PID_MONITOR=$(cat monitor.pid)
            ssh ${PI_USER}@${PI_IP} "kill $PID_MONITOR 2>/dev/null || true"
            rm monitor.pid

            # 5. Esperar al Suscriptor
            wait $SUB_PID

            echo "❄️ Corrida $i terminada. Enfriando por 10 segundos..."
            sleep 10
        done
    done
done

echo "✅ ¡Todas las pruebas de seguridad finalizaron!"
