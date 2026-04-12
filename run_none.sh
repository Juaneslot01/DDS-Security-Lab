#!/bin/bash

# --- CONFIGURACIÓN ---
ESCENARIO="none"
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000
PI_IP="192.168.20.49"
PI_USER="pi"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

# Crear carpetas si no existen
mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🚀 Iniciando Escenario Base: [NONE] (Sin Seguridad)"

for payload in "${PAYLOADS[@]}"; do
    echo "======================================================"
    echo "📦 Payload: [$payload Bytes]"
    echo "======================================================"

    for ((i=1; i<=CORRIDAS; i++)); do
        echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

        CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${ESCENARIO}_${payload}B_run${i}.csv"
        CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${ESCENARIO}_${payload}B_run${i}.csv"

        # 1. Limpieza total (Local y Remota)
        docker rm -f dds_subscriber > /dev/null 2>&1
        ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher > /dev/null 2>&1"

        # 2. Arrancar Suscriptor (PC)
        # Se queda en segundo plano (&) redirigiendo la latencia al CSV
        docker run --rm --name dds_subscriber --net=host --ipc=host -w /app \
            dds-lab ./build/payload subscriber ${ESCENARIO} > ${CSV_LATENCIA} 2>/dev/null &
        SUB_PID=$!

        sleep 2 # Esperar a que el suscriptor esté listo

        # 3. Arrancar el Monitor en la Pi (Ahora con permisos)
        ssh ${PI_USER}@${PI_IP} "nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!" > monitor.pid

        # 4. Arrancar Publicador (Pi)
        ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${ESCENARIO}"

        # 5. Kill Switch: Dar 10 segundos para cerrar y si no, matar el suscriptor
        sleep 10
        PID_MONITOR=$(cat monitor.pid)
        ssh ${PI_USER}@${PI_IP} "kill -9 $PID_MONITOR 2>/dev/null || true"
        rm monitor.pid

        if ps -p $SUB_PID > /dev/null; then
            echo "⚠️ Suscriptor no cerró solo. Forzando cierre..."
            docker rm -f dds_subscriber > /dev/null 2>&1
        fi

        echo "❄️ Corrida $i terminada. Enfriando por 10 segundos..."
        sleep 10
    done
done

echo "✅ Escenario NONE completado. ¡Datos base listos!"
