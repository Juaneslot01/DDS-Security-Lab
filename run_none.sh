#!/bin/bash

# --- CONFIGURACIÓN ---
ESCENARIO="none"
PAYLOADS=("256" "1024" "16384")
CORRIDAS=30
MENSAJES=11000
PI_IP="10.0.0.2"
PI_USER="pi"
DIR_PI="/home/pi/DDS-Security-Lab"
DIR_PC=$(pwd)

# Aislamiento de Núcleo (Usaremos el Core 0 para evitar saltos de contexto)
CPU_CORE="0"

mkdir -p ${DIR_PC}/resultados_latencia
ssh ${PI_USER}@${PI_IP} "mkdir -p ${DIR_PI}/resultados_recursos"

echo "🛡️ Iniciando experimento bajo condiciones controladas [ESCENARIO: $ESCENARIO]"
echo "⚠️ Asegúrate de que ptp4l esté corriendo en otra terminal para la sincronización."

for payload in "${PAYLOADS[@]}"; do
    echo "======================================================"
    echo "📦 Payload: [$payload Bytes] | Core: $CPU_CORE"
    echo "======================================================"

    # --- PASO 1: WARM START (Hardware/System) ---
    # Enviamos una ráfaga inicial de 5 segundos para estabilizar la frecuencia de la CPU
    # y llenar los buffers de red antes de empezar a registrar datos reales.
    echo "🔥 Fase de Calentamiento (Warm-up)..."
    docker run --rm --cpuset-cpus="$CPU_CORE" --net=host --ipc=host dds-lab ./build/payload subscriber $ESCENARIO > /dev/null 2>&1 &
    WARM_SUB_PID=$!
    sleep 2
    ssh ${PI_USER}@${PI_IP} "docker run --rm --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher 5000 $payload 0 $ESCENARIO" > /dev/null 2>&1
    docker rm -f dds_subscriber > /dev/null 2>&1
    sleep 5 # Breve respiro para estabilizar

    for ((i = 1; i <= CORRIDAS; i++)); do
        echo "▶️ Corrida $i de $CORRIDAS..."

        CSV_LATENCIA="${DIR_PC}/resultados_latencia/Latencia_${ESCENARIO}_${payload}B_run${i}.csv"
        CSV_RECURSOS="${DIR_PI}/resultados_recursos/Recursos_${ESCENARIO}_${payload}B_run${i}.csv"

        # --- PASO 2: MEDIR IDLE (Pre-flight check) ---
        # Verificamos que la CPU de la Pi esté libre antes de arrancar.
        # Capturamos el % idle de los últimos 2 segundos.
        IDLE_VALUE=$(ssh ${PI_USER}@${PI_IP} "top -bn2 | grep 'Cpu(s)' | tail -n 1 | awk '{print \$8}'")
        echo "📊 Estado Idle de la Pi: $IDLE_VALUE% libre."

        # Limpieza de seguridad
        docker rm -f dds_subscriber >/dev/null 2>&1
        ssh ${PI_USER}@${PI_IP} "docker rm -f pi_publisher > /dev/null 2>&1"

        # --- PASO 3: ARRANCAR MONITOREO (Frecuencia, Temp, CPU) ---
        # El monitor ahora registra Freq_MHz para detectar Throttling.
        ssh ${PI_USER}@${PI_IP} "nohup ${DIR_PI}/monitor_recursos.sh ${CSV_RECURSOS} > /dev/null 2>&1 & echo \$!" > monitor.pid

        # --- PASO 4: EJECUCIÓN CON AISLAMIENTO DE NÚCLEO ---
        # Suscriptor en PC (Limitado a Core 0)
        docker run --rm --name dds_subscriber --cpuset-cpus="$CPU_CORE" --net=host --ipc=host -w /app \
          dds-lab ./build/payload subscriber ${ESCENARIO} >${CSV_LATENCIA} 2>/dev/null &
        SUB_PID=$!

        sleep 2

        # Publicador en Pi (Limitado a Core 0)
        ssh ${PI_USER}@${PI_IP} "timeout 300 docker run --rm --name pi_publisher --cpuset-cpus='$CPU_CORE' --net=host --ipc=host -w /app dds-lab ./build/payload publisher ${MENSAJES} ${payload} 1000 ${ESCENARIO}"

        # --- PASO 5: LIMPIEZA Y ENFRIAMIENTO ---
        PID_MONITOR=$(cat monitor.pid)
        ssh ${PI_USER}@${PI_IP} "kill -9 $PID_MONITOR 2>/dev/null || true"
        rm monitor.pid

        sleep 5
        if ps -p $SUB_PID >/dev/null; then
          docker rm -f dds_subscriber >/dev/null 2>&1
        fi

        # Enfriamiento: Un respiro más largo ayuda a evitar que el calor se acumule
        echo "❄️ Enfriando procesadores (15s)..."
        sleep 15
    done
done

echo "📥 Sincronizando logs de salud (Frecuencia/Temp/CPU)..."
rsync -avzP ${PI_USER}@${PI_IP}:${DIR_PI}/resultados_recursos/ ./resultados_recursos_pi/

echo "✅ Experimento terminado con éxito bajo condiciones controladas."
