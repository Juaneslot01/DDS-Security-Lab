#!/bin/bash
# monitor_recursos.sh - Versión para Tesis (Captura Hardware + Contenedor)

CONTENEDOR_NOMBRE="pi_publisher"
ARCHIVO_SALIDA=$1

# 1. Encabezado con métricas de salud de hardware
echo "Timestamp,CPU(%),RAM(MB),Freq_MHz,Temp_C" > "$ARCHIVO_SALIDA"

while true; do
    # Captura métricas de Docker
    METRICAS=$(docker stats --no-stream --format '{"cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}"}' $CONTENEDOR_NOMBRE 2>/dev/null)

    if [ ! -z "$METRICAS" ]; then
        # 2. Extraer CPU y RAM del contenedor
        CPU=$(echo "$METRICAS" | grep -o '"cpu":"[^"]*' | cut -d'"' -f4 | tr -d '%')
        RAM_RAW=$(echo "$METRICAS" | grep -o '"mem":"[^"]*' | cut -d'"' -f4 | awk '{print $1}')
        RAM=$(echo "$RAM_RAW" | sed 's/[a-zA-Z]//g')

        # 3. EXTRA: Capturar salud del hardware (Vital para explicar anomalías)
        # Frecuencia actual del procesador en MHz
        FREQ_RAW=$(vcgencmd measure_clock arm | cut -d'=' -f2)
        FREQ_MHZ=$((FREQ_RAW / 1000000))

        # Temperatura del chip
        TEMP=$(vcgencmd measure_temp | cut -d'=' -f2 | tr -d "'C")

        # 4. Registro con marca de tiempo (Epoch para facilitar gráficas en Python/Excel)
        TIMESTAMP=$(date +%s)
        echo "$TIMESTAMP,$CPU,$RAM,$FREQ_MHZ,$TEMP" >> "$ARCHIVO_SALIDA"
    fi

    sleep 1
done
