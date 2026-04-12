#!/bin/bash
# monitor_recursos.sh - Ejecutar en la Raspberry Pi

CONTENEDOR_NOMBRE="pi_publisher"
ARCHIVO_SALIDA=$1

# Encabezado del CSV
echo "Tiempo,CPU(%),RAM(MB)" > "$ARCHIVO_SALIDA"

while true; do
    # 1. Captura en formato JSON (Evita errores de parseo por columnas o espacios)
    METRICAS=$(docker stats --no-stream --format '{"cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}"}' $CONTENEDOR_NOMBRE 2>/dev/null)

    if [ ! -z "$METRICAS" ]; then
        # 2. Extraer CPU: elimina el símbolo '%'
        CPU=$(echo "$METRICAS" | grep -o '"cpu":"[^"]*' | cut -d'"' -f4 | tr -d '%')

        # 3. Extraer RAM:
        # Tomamos el valor antes del '/', separamos el número de la unidad y eliminamos letras (MiB, GiB, B)
        # Esto garantiza que el CSV sea puramente numérico para facilitar las gráficas
        RAM_RAW=$(echo "$METRICAS" | grep -o '"mem":"[^"]*' | cut -d'"' -f4 | awk '{print $1}')
        RAM=$(echo "$RAM_RAW" | sed 's/[a-zA-Z]//g')

        # 4. Registro con marca de tiempo
        FECHA=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$FECHA,$CPU,$RAM" >> "$ARCHIVO_SALIDA"
    fi

    # Frecuencia de muestreo (1 segundo es ideal para ver picos de cifrado en FastDDS)
    sleep 1
done
