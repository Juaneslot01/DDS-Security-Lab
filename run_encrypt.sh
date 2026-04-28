#!/bin/bash

# --- CONFIGURACIÓN ---
ESCENARIO="encrypt"
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000
PI_IP="10.0.0.2"
PI_USER="pi"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

# 🎯 CONFIGURACIÓN DE AISLAMIENTO (Core 0 para evitar ruidos de scheduling)
CPU_CORE="0"

# Asegurar que las carpetas existen
mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🧪 Iniciando Protocolo de Laboratorio: [$ESCENARIO]"
echo "📍 Aislamiento de Núcleo: Core $CPU_CORE | Warm Start: Activado"

for payload in "${PAYLOADS[@]}"; do
    echo "======================================================"
    echo "📦 Payload: [$payload Bytes]"
    echo "======================================================"

    # --- 1. FASE DE CALENTAMIENTO (Hardware Warm Start) ---
    # Una ráfaga rápida para subir la frecuencia del CPU y preparar las cachés
    # antes de empezar a registrar los datos reales.
    echo "🔥 Calentando procesadores para cifrado AES..."
    docker run --rm --name dds_warmup --cpuset-cpus="$CPU_CORE" --net=host --ipc=host dds-lab ./build/payload subscriber $ESCENARIO > /dev/null 2>&1 &
    sleep 2
    ssh ${PI_USER}@${PI_IP} "docker run --rm --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher 5000 $payload 0 $ESCENARIO" > /dev/null 2>&1
    docker rm -f dds_warmup > /dev/null 2>&1
    sleep 5

    for ((i=1; i<=CORRIDAS; i++)); do
        echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

        CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${ESCENARIO}_${payload}B_run${i}.csv"
        CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${ESCENARIO}_${payload}B_run${i}.csv"

        # --- 2. VERIFICACIÓN DE IDLE (Pre-flight check) ---
        # Nos aseguramos de que el núcleo 0 esté libre antes de arrancar.
        IDLE_VAL=$(ssh ${PI_USER}@${PI_IP} "top -bn2 | grep 'Cpu(s)' | tail -n 1 | awk '{print \$8}'")
        echo "📊 Pre-check Idle en Pi (Core 0): $IDLE_VAL% libre."

        # Limpieza total preventiva
        docker rm -f dds_subscriber > /dev/null 2>&1
        ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher > /dev/null 2>&1"

        # --- 3. ARRANCAR MONITOR EN LA PI ---
        # Asegúrate de usar el monitor que registra Freq_MHz y Temp_C
        ssh ${PI_USER}@${PI_IP} "bash -c 'nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!'" > monitor.pid

        # --- 4. EJECUCIÓN DEL EXPERIMENTO (Aislamiento de Núcleo) ---
        # Suscriptor (PC - Core 0)
        docker run --rm --name dds_subscriber --cpuset-cpus="$CPU_CORE" --net=host --ipc=host -w /app \
            dds-lab ./build/payload subscriber ${ESCENARIO} > ${CSV_LATENCIA} 2>/dev/null &
        SUB_PID=$!

        sleep 2

        # Publicador (Pi - Core 0)
        ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${ESCENARIO}"

        # --- 5. DETENCIÓN Y LIMPIEZA ---
        PID_MONITOR=$(cat monitor.pid)
        if [ ! -z "$PID_MONITOR" ]; then
            ssh ${PI_USER}@${PI_IP} "kill -9 $PID_MONITOR 2>/dev/null || true"
        fi
        rm monitor.pid

        # Esperar cierre del suscriptor y forzar si es necesario
        sleep 5
        if ps -p $SUB_PID > /dev/null; then
            echo "⚠️ Suscriptor colgado. Forzando cierre..."
            docker rm -f dds_subscriber > /dev/null 2>&1
        fi

        # --- 6. FASE DE ENFRIAMIENTO ---
        # Vital para evitar el acumulamiento térmico en los 30 ciclos
        echo "❄️ Estabilizando temperatura (15 segundos)..."
        sleep 15
    done
done

echo "📥 Sincronizando resultados cifrados al PC..."
rsync -avzP ${PI_USER}@${PI_IP}:${DIR_PI}/resultados_recursos/ ./resultados_recursos_pi/

echo "✅ [ESCENARIO ENCRYPT] Finalizado con éxito bajo control térmico y de núcleo."
