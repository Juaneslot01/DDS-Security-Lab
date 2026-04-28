#!/bin/bash

# --- CONFIGURACIÓN ---
ESCENARIO="access"
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000
PI_IP="10.0.0.2"
PI_USER="pi"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

# 🎯 CONFIGURACIÓN DE DETERMINISMO (Aislamiento total en Core 0)
CPU_CORE="0"

# Asegurar que las carpetas existen
mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🛡️ Iniciando Escenario FULL SECURITY: [$ESCENARIO]"
echo "📍 Configuración: Core Pinning ($CPU_CORE) + Monitorización Térmica"

for payload in "${PAYLOADS[@]}"; do
    echo "======================================================"
    echo "📦 Payload: [$payload Bytes]"
    echo "======================================================"

    # --- 1. FASE DE CALENTAMIENTO (Hardware Warm Start) ---
    # Es vital para que el chequeo de permisos inicial no ensucie los datos
    # y la CPU alcance su frecuencia de operación estable.
    echo "🔥 Calentando motores para el stack completo de seguridad..."
    docker run --rm --name dds_warmup --cpuset-cpus="$CPU_CORE" --net=host --ipc=host dds-lab ./build/payload subscriber $ESCENARIO > /dev/null 2>&1 &
    sleep 3
    ssh ${PI_USER}@${PI_IP} "docker run --rm --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher 5000 $payload 0 $ESCENARIO" > /dev/null 2>&1
    docker rm -f dds_warmup > /dev/null 2>&1
    sleep 5

    for ((i=1; i<=CORRIDAS; i++)); do
        echo "▶️ Ejecutando corrida $i de $CORRIDAS..."

        CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${ESCENARIO}_${payload}B_run${i}.csv"
        CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${ESCENARIO}_${payload}B_run${i}.csv"

        # --- 2. VERIFICACIÓN DE IDLE (Pre-flight check) ---
        # Si el % idle es bajo antes de empezar, algo está interfiriendo.
        IDLE_VAL=$(ssh ${PI_USER}@${PI_IP} "top -bn2 | grep 'Cpu(s)' | tail -n 1 | awk '{print \$8}'")
        echo "📊 Pre-check Idle en Pi (Core 0): $IDLE_VAL% libre."

        # Limpieza total preventiva
        docker rm -f dds_subscriber > /dev/null 2>&1
        ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher > /dev/null 2>&1"

        # --- 3. ARRANCAR MONITOR EN LA PI ---
        # Este monitor registra Freq_MHz y Temp_C para detectar Thermal Throttling
        ssh ${PI_USER}@${PI_IP} "bash -c 'nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!'" > monitor.pid

        # --- 4. EJECUCIÓN (Aislamiento de Núcleo Forzado) ---
        # Suscriptor (PC - Limitado al Core 0)
        docker run --rm --name dds_subscriber --cpuset-cpus="$CPU_CORE" --net=host --ipc=host -w /app \
            dds-lab ./build/payload subscriber ${ESCENARIO} > ${CSV_LATENCIA} 2>/dev/null &
        SUB_PID=$!

        sleep 3 # Un segundo extra para que el handshake de seguridad se estabilice

        # Publicador (Pi - Limitado al Core 0)
        ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${ESCENARIO}"

        # --- 5. DETENCIÓN Y LIMPIEZA ---
        PID_MONITOR=$(cat monitor.pid)
        if [ ! -z "$PID_MONITOR" ]; then
            ssh ${PI_USER}@${PI_IP} "kill -9 $PID_MONITOR 2>/dev/null || true"
        fi
        rm monitor.pid

        sleep 5
        if ps -p $SUB_PID > /dev/null; then
            echo "⚠️ Suscriptor lento (Handshake pesado?). Forzando cierre..."
            docker rm -f dds_subscriber > /dev/null 2>&1
        fi

        # --- 6. FASE DE ENFRIAMIENTO EXTENDIDA ---
        # Como este escenario usa más CPU, subimos el enfriamiento a 20s
        echo "❄️ Disipando calor acumulado (20 segundos)..."
        sleep 20
    done
done

echo "📥 Sincronizando resultados finales a la base..."
rsync -avzP ${PI_USER}@${PI_IP}:${DIR_PI}/resultados_recursos/ ./resultados_recursos_pi/

echo "✅ [ESCENARIO ACCESS] Completado."
