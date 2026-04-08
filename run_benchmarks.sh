#!/bin/bash
# run_benchmarks.sh - Ejecutar en PC

# --- CONFIGURACIÓN ---
PI_USER="pi"
PI_IP="192.168.20.26"
DIR_PI="/home/pi/dds-security-lab"   # Ruta del proyecto en la Pi
DIR_PC=$(pwd)                        # Ruta actual en CachyOS

ESCENARIOS=("none" "auth" "encrypt" "access")
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000 # 1000 de calentamiento + 10000 de medición

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

            # 1. Arrancar Suscriptor en el PC (en segundo plano)
            # NOTA: Ajusta los argumentos './build/payload' según tu código en C++
            docker run --rm --net=host --ipc=host \
                -v ${DIR_PC}/resultados_latencia:/app/resultados_latencia \
                dds-lab ./build/payload subscriber ${escenario} ${payload} > ${CSV_LATENCIA} &
            SUB_PID=$!

            sleep 2 # Dar tiempo a que el Suscriptor esté escuchando

            # 2. Arrancar el Monitor de Recursos en la Pi (en segundo plano remoto)
            ssh ${PI_USER}@${PI_IP} "nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!" > monitor.pid

            # 3. Arrancar Publicador en la Pi (esto bloquea hasta que termine de enviar)
            ssh ${PI_USER}@${PI_IP} "docker run --rm --name pi_publisher --net=host --ipc=host dds-lab ./build/payload publisher ${MENSAJES} ${payload} ${escenario}"

            # 4. Detener el Monitor de Recursos en la Pi
            PID_MONITOR=$(cat monitor.pid)
            ssh ${PI_USER}@${PI_IP} "kill $PID_MONITOR"
            rm monitor.pid

            # 5. Esperar a que el contenedor del Suscriptor local termine correctamente
            wait $SUB_PID

            # 6. Enfriamiento para evitar Thermal Throttling en la CPU ARM
            echo "❄️ Corrida $i terminada. Enfriando por 10 segundos..."
            sleep 10
        done
    done
done

echo "✅ ¡Todas las pruebas finalizaron! Puedes traer los archivos de recursos usando scp."
