# **DDS-Security-Lab: Benchmarking de Seguridad en Sistemas IoT**

Este laboratorio permite evaluar el impacto de los niveles de seguridad del estándar **DDS Security v1.1** sobre el rendimiento (latencia y consumo de recursos) en una arquitectura distribuida que conecta un PC de alto rendimiento y un dispositivo embebido ARM (Raspberry Pi).

## **Arquitectura del Laboratorio**

### **1. Modelo Distribuido**
El experimento utiliza dos nodos físicos para medir el impacto real de la red y el procesamiento criptográfico sin interferencias de procesos compartidos:

* **Nodo Suscriptor (PC):** Actúa como el orquestador del experimento y recolector de métricas de latencia.
* **Nodo Publicador (Raspberry Pi):** Simula un dispositivo IoT que cifra y envía telemetría. Es el nodo monitoreado en consumo de CPU y RAM.

### **2. Escenarios de Seguridad**
Se implementaron 4 niveles de seguridad utilizando una infraestructura de clave pública (PKI) basada en **RSA-2048**:

| Escenario | Plugin Auth | Plugin Access | Plugin Crypto | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `none` | ❌ | ❌ | ❌ | Línea base sin seguridad. |
| `auth` | ✅ | ✅ | ❌ | Autenticación mutua PKI-DH. |
| `encrypt` | ✅ | ✅ | ✅ | Autenticación + Cifrado AES-GCM-256 (Gobernanza). |
| `access` | ✅ | ✅ | ✅ | Control de acceso granular por tópico + Cifrado. |

## **Implementación Técnica**

* **Latencia E2E:** Capturada en C++ con `std::chrono::high_resolution_clock`. El timestamp se inserta en el payload para evitar problemas de sincronización de relojes entre dispositivos.
* **Monitoreo de Recursos:** El script `monitor_recursos.sh` captura el consumo del contenedor en la Raspberry Pi mediante `docker stats` en formato JSON, asegurando precisión numérica para el análisis.
* **Validación Preventiva:** El código C++ verifica la existencia de certificados antes de iniciar el participante DDS, evitando fallos de segmentación o comportamientos indefinidos.

## **Requisitos del Sistema**

Toda la compilación y ejecución se realiza mediante contenedores, por lo que no es necesario instalar las librerías de FastDDS en el sistema host. Solo se requiere:

1.  **Docker:** Instalado en el PC y en la Raspberry Pi.
2.  **SSH:** Configurado con acceso sin contraseña desde el PC hacia la Raspberry Pi (`ssh-copy-id`).
3.  **Python 3:** En el PC (únicamente para la generación de gráficas finales).

## **Instrucciones de Ejecución**

### **1. Generar Artefactos de Seguridad**
En la raíz del proyecto (en tu PC), genera la CA y las llaves necesarias. Estos archivos serán copiados automáticamente a los contenedores durante el proceso de construcción:
```bash
bash generate_security_artifacts.sh
```

### 2. Construcción de Imágenes (Docker)
Debes construir la imagen en ambas máquinas. El Dockerfile se encarga de resolver las dependencias de FastDDS y compilar el código C++:

```bash
docker build -t dds-lab .
```

### 3. Ejecución del Benchmark Automático
Desde tu PC, lanza el orquestador maestro. Este script automatiza las 360 corridas, gestiona los contenedores remotos vía SSH y recolecta los archivos CSV de resultados:

```bash
chmod +x run_benchmarks.sh
./run_benchmarks.sh
```

### 4. Generación de Gráficas
Una vez finalizadas las pruebas, utiliza el entorno virtual de Python para procesar los datos y generar las visualizaciones para la tesis:

```bash
# Configurar entorno virtual (solo la primera vez)
python3 -m venv venv
source venv/bin/activate.fish  # O venv/bin/activate según tu shell

# Instalar dependencias y graficar
pip install pandas matplotlib seaborn
python3 graficar_resultados.py
```

## Estructura del Proyecto

- payloadPubSubMain.cxx: Aplicación principal en C++.
- SecurityConfig.cxx: Lógica de inyección de plugins de seguridad y validación de archivos.
- run_benchmarks.sh: Orquestador maestro del experimento.
- monitor_recursos.sh: Script de captura de métricas en la Raspberry Pi.
- Dockerfile: Entorno reproducible basado en Ubuntu 22.04 y FastDDS.
