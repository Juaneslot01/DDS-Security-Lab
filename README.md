# **DDS-Security-Lab**

## **Arquitectura del Laboratorio**

### **1. Modelo de Comunicación y Middleware**

Se implementó el middleware eProsima FastDDS, utilizando el estándar RTPS (Real-Time Publish-Subscribe) sobre el protocolo de transporte UDP/IP.

* **DomainParticipant**: Se configuró un dominio único ($DomainID=0$) para asegurar que el descubrimiento sea inmediato dentro de la red local.
* **Topic**: Se definió un tópico de tipo dinámico para permitir el intercambio de diferentes tamaños de payload sin re-compilar el núcleo del middleware.
* **QoS**: Para las pruebas de latencia, se configuró una política de Best Effort y Volatile Durability, minimizando el re-envío de paquetes y asegurando que estamos midiendo la velocidad pura del transporte y el cifrado.

### **2. Infraestructura de Red en Contenedores**

Para eliminar el overhead de la virtualización de red de Docker (puentes de software o NAT), se implementaron las siguientes estrategias:

* **Host Networking Mode:** El contenedor comparte el stack de red del kernel del host. Esto permite que el tráfico UDP de DDS no pase por capas de traducción de direcciones, logrando una latencia cercana al "bare-metal".
* **Shared Memory IPC:** FastDDS utiliza un transporte de memoria compartida para procesos en la misma máquina. Habilitar esto permite que el Publicador y el Suscriptor se comuniquen mediante segmentos de memoria global, reduciendo drásticamente la latencia en comparación con el uso de sockets de red tradicionales.

## **Implementación Técnica**

La implementación se divide en tres capas: captura de métricas, gestión de memoria y seguridad.

### **1. Captura de Métricas**

Se desarrolló un motor de medición en C++ utilizando la librería <chrono>. A diferencia de las funciones de tiempo estándar, se utilizó std::chrono::high_resolution_clock para obtener una precisión de nanosegundos, aunque los resultados se truncan a microsegundos ($\mu s$) para el análisis estadístico.

* **Proceso de Medición:**  El Publicador inserta un timestamp de alta resolución dentro del payload. Al recibirlo, el Suscriptor calcula la diferencia ($t_{recepción} - t_{emisión}$), eliminando la necesidad de sincronización de relojes externos si ambos nodos corren en el mismo hardware.

### **2. Gestión de Payloads y Buffer**

Se implementó un sistema de buffers dinámicos para simular diferentes tipos de datos (desde telemetría ligera hasta flujos de video).

* **Fragmentación:** Se monitoreó el comportamiento del middleware cuando el payload supera el MTU (Maximum Transmission Unit) estándar de 1500 bytes, forzando a FastDDS a gestionar la fragmentación y el re-ensamblaje de paquetes.


## **Como Correr el Experimento**

### **1. Preparación del Host:**

```bash
Bash
# Crear la carpeta donde caerán los resultados desde el contenedor
mkdir -p resultados_csv

# Configurar el entorno de Python para las gráficas (solo una vez)
python3 -m venv venv
source venv/bin/activate
pip install pandas matplotlib seaborn
deactivate
```

### **2. Construcción del Contenedor:**
```bash
Bash
# Construir la imagen Docker
docker build -t dds-lab .
```

### **3. Ejecución del Experimento:**

**A. El suscriptor**

```bash
# 1. Entrar al contenedor con privilegios de red y volumen mapeado
docker run -it --rm --net=host --ipc=host -v $(pwd)/resultados_csv:/app/resultados_csv dds-lab

# 2. Ejecutar el suscriptor (Ejemplo: prueba de 1KB)
# El comando 'tee' escribe en el archivo y te muestra los datos en pantalla
./build/payload subscriber | tee resultados_csv/latencia_1KB_no_sec.csv
```

**B. El publicador**

```bash
# 1. Entrar al contenedor
docker run -it --rm --net=host --ipc=host dds-lab

# 2. Ejecutar el publicador
# Parámetros: [Mensajes] [Tamaño_Bytes] [Espera_microsegundos]
./build/payload publisher 100 1024 100000
```
