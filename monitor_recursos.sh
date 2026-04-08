#!/bin/bash
# monitor_recursos.sh - Ejecutar en la Raspberry Pi

CONTENEDOR_NOMBRE="pi_publisher"
ARCHIVO_SALIDA=$1

echo "Tiempo,CPU(%),RAM(MB)" > "$ARCHIVO_SALIDA"

# Bucle infinito que captura las métricas cada 1 segundo
while true; do
    # Extraer métricas usando docker stats sin formato extra
    METRICAS=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" $CONTENEDOR_NOMBRE 2>/dev/null)

    if [ ! -z "$METRICAS" ]; then
        # Limpiar el texto para dejar solo los números
        CPU=$(echo $METRICAS | cut -d',' -f1 | tr -d '%')
        RAM=$(echo $METRICAS | cut -d',' -f2 | awk '{print $1}' | tr -d 'MiB')

        FECHA=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$FECHA,$CPU,$RAM" >> "$ARCHIVO_SALIDA"
    fi
    sleep 1
done
