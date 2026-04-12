#!/bin/bash

# --- CONFIGURACIÓN ---
ESCENARIO="auth" # Cambia esto para cada script (auth, encrypt, access)
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000
PI_IP="192.168.20.49"
PI_USER="pi"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

echo "🚀 Iniciando Escenario: [$ESCENARIO]"

for payload in "${PAYLOADS[@]}"; do
    echo "======================================================"
    echo "📦 Payload: [$payload Bytes]"
    echo "======================================================"

    for ((i=1; i<=CORRIDAS; i++)); do
        echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

        CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${ESCENARIO}_${payload}B_run${i}.csv"

        # 1. Limpieza total (Local y Remota)
        docker rm -f dds_subscriber > /dev/null 2>&1
        ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher > /dev/null 2>&1"

        # 2. Arrancar Suscriptor (PC)
        # Usamos --name para poder matarlo luego fácilmente
        docker run --rm --name dds_subscriber --net=host --ipc=host -w /app \
            dds-lab ./build/payload subscriber ${ESCENARIO} > ${CSV_LATENCIA} 2>/dev/null &
        SUB_PID=$!

        sleep 2

        # 3. Arrancar Publicador (Pi)
        ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${ESCENARIO}"

        # 4. TRUCO MAESTRO: Evitar el bloqueo
        # Esperamos 5 segundos a que el suscriptor termine de procesar lo último
        sleep 5
        # Si el suscriptor sigue vivo (porque perdió algún paquete), lo matamos
        if ps -p $SUB_PID > /dev/null; then
            echo "⚠️ Suscriptor lento o con paquetes perdidos. Cerrando..."
            docker rm -f dds_subscriber > /dev/null 2>&1
        fi

        echo "❄️ Corrida $i terminada. Enfriando..."
        sleep 10
    done
done
