# **DDS-Security-Lab: Benchmarking de Seguridad en Sistemas IoT**

Este laboratorio evalúa el impacto de los perfiles de seguridad del estándar **DDS Security v1.1** sobre el rendimiento (latencia unidireccional y consumo de recursos) en una arquitectura distribuida que conecta un PC con Linux y un dispositivo embebido ARM (Raspberry Pi 4 Model B), usando eProsima Fast DDS.

## **Arquitectura del Laboratorio**

### **1. Topología**
El experimento utiliza dos nodos físicos conectados por Ethernet punto a punto (red aislada, direccionamiento estático):

| Nodo | Hardware | Rol DDS | Qué se mide |
| :--- | :--- | :--- | :--- |
| Raspberry Pi (`10.0.0.2`) | Raspberry Pi 4 Model B (Cortex-A72) | **Publicador**: genera, protege (firma/cifra) y envía los mensajes | CPU, RAM, frecuencia y temperatura del contenedor publicador |
| PC (`10.0.0.1`) | PC con Linux | **Suscriptor** y orquestador del experimento | Latencia unidireccional de cada mensaje |

### **2. Perfiles de Seguridad**
Los cuatro escenarios son **perfiles acumulativos**, no mecanismos aislados. La infraestructura de clave pública (PKI) usa **RSA-2048** (certificados X.509 firmados con SHA-256). En todos los escenarios con seguridad se cargan los tres plugins integrados de Fast DDS (`builtin.PKI-DH`, `builtin.Access-Permissions`, `builtin.AES-GCM-GMAC`); lo que cambia entre escenarios es el documento de gobernanza (`security/xml/gov_<escenario>.xml`):

| Política (gobernanza) | `none` | `auth` | `encrypt` | `access` |
| :--- | :---: | :---: | :---: | :---: |
| Autenticación mutua PKI-DH | ❌ | ✅ | ✅ | ✅ |
| `allow_unauthenticated_participants` | — | `false` | `false` | `false` |
| `enable_join_access_control` | — | `true` | `true` | `true` |
| `discovery_protection_kind` | — | `SIGN` | `ENCRYPT` | `ENCRYPT` |
| `liveliness_protection_kind` | — | `SIGN` | `ENCRYPT` | `ENCRYPT` |
| `rtps_protection_kind` | — | `NONE` | `ENCRYPT` | `ENCRYPT` |
| `metadata_protection_kind` (tópico) | — | `NONE` | `ENCRYPT` | `ENCRYPT` |
| `data_protection_kind` (tópico) | — | `NONE` | `ENCRYPT` | `ENCRYPT` |
| `enable_read_access_control` / `enable_write_access_control` | — | `false` | `false` | `true` |

La diferencia entre `encrypt` y `access` es únicamente la verificación de permisos de lectura/escritura por tópico.

## **Implementación Técnica**

* **Latencia unidireccional (extremo a extremo, a nivel de aplicación):** el publicador toma una marca de tiempo con `std::chrono::high_resolution_clock` justo antes de `writer_->write()` y la inserta en el mensaje; el suscriptor toma otra al recibirlo en `on_data_available()`. La diferencia incluye serialización, protección criptográfica en el emisor, transporte por la red, verificación/descifrado en el receptor y deserialización. Como las dos marcas de tiempo provienen de **relojes distintos**, la medición depende de que ambos equipos estén sincronizados (PTP); el desfase residual entre relojes se suma directamente a la latencia medida.
* **Modo de publicación síncrono:** el DataWriter usa `SYNCHRONOUS_PUBLISH_MODE`, de modo que `write()` no retorna hasta entregar el mensaje a la pila de red.
* **Monitoreo de recursos:** `monitor_recursos.sh` registra en la Raspberry Pi, aproximadamente una vez por segundo, CPU y memoria del contenedor publicador (`docker stats`), frecuencia del procesador y temperatura (`vcgencmd`).
* **Validación preventiva:** el código C++ verifica la existencia de los certificados y documentos firmados antes de crear el participante DDS.

## **Gestión de Material Criptográfico**

* Las claves privadas, certificados y documentos firmados (`security/pki/`, `security/signed/`) **no se versionan** (están en `.gitignore`) y **no se incluyen en la imagen Docker** (están en `.dockerignore`).
* Se generan localmente con `generate_security_artifacts.sh` y se montan en los contenedores en **solo lectura** al ejecutar (`-v ./security:/app/security:ro`).
* Una versión anterior de este repositorio publicó claves privadas de laboratorio. Esas credenciales se consideran comprometidas: se eliminaron del historial de Git, se generó una CA nueva y no deben reutilizarse.

## **Requisitos del Sistema**

Toda la compilación y ejecución se realiza en contenedores, por lo que no es necesario instalar Fast DDS en los equipos. Se requiere:

1. **Docker** en el PC y en la Raspberry Pi.
2. **SSH** sin contraseña desde el PC hacia la Raspberry Pi (`ssh-copy-id pi@10.0.0.2`).
3. **Sincronización PTP** entre ambos equipos (ver sección siguiente).
4. **Python 3** en el PC (solo para el análisis en `results.ipynb`).

> El PC debe ejecutar Linux nativo: en Docker Desktop (macOS/Windows) `--net=host` y `--cpuset-cpus` no se comportan igual.

### **Versiones utilizadas**

| Componente | Versión |
| :--- | :--- |
| Imagen base | Ubuntu 22.04 |
| ROS 2 (paquetes de Fast DDS) | Humble |
| Fast DDS (`ros-humble-fastrtps`) | _completar_ |
| Fast CDR (`ros-humble-fastcdr`) | _completar_ |
| OpenSSL (`libssl-dev`) | _completar_ |
| Docker (PC / Pi) | _completar_ |
| Sistema operativo del PC / de la Pi | _completar_ |

Para obtener las versiones de la imagen:
```bash
docker run --rm dds-lab bash -c "dpkg -l | grep -E 'fastrtps|fastcdr|libssl-dev' ; openssl version"
```

## **Instrucciones de Ejecución**

### **1. Preparar los equipos**
En ambos equipos, para reducir la variabilidad durante las mediciones:
```bash
sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer snapd.service
echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### **2. Generar los artefactos de seguridad**
En la raíz del proyecto, en el PC:
```bash
bash generate_security_artifacts.sh
```
Copia la misma PKI a la Raspberry Pi (ambos nodos deben compartir la CA):
```bash
rsync -av security/ pi@10.0.0.2:/home/pi/DDS-Security-Lab/security/
```
Estos archivos no se copian a la imagen: se montan en solo lectura al ejecutar los contenedores.

### **3. Construir la imagen (Docker)**
En ambas máquinas:
```bash
docker build -t dds-lab .
```

### **4. Ejecutar los benchmarks**
Desde la raíz del proyecto en el PC, ejecuta un script por escenario. Cada uno realiza 30 corridas por cada tamaño de payload (256 B, 1 KB y 16 KB), con 11 000 mensajes por corrida, calentamiento previo y enfriamiento entre corridas:
```bash
./run_none.sh
./run_auth.sh
./run_encrypt.sh
./run_access.sh
```
Los resultados quedan en:
* `resultados_latencia/Latencia_<escenario>_<payload>B_run<i>.csv` (PC)
* `resultados_recursos_pi/Recursos_<escenario>_<payload>B_run<i>.csv` (copiados desde la Pi)

> Haz una copia de respaldo de estos CSV fuera del equipo (por ejemplo, en la nube) al terminar cada escenario.

### **5. Análisis**
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
jupyter notebook results.ipynb
```

## **Estructura del Proyecto**

- `payloadPubSubMain.cxx`: punto de entrada (modo publicador o suscriptor).
- `payloadPublisher.cxx` / `payloadSubscriber.cxx`: nodos DDS y medición de latencia.
- `payload.idl`: tipo de datos (número de secuencia, marca de tiempo y carga útil variable).
- `security/SecurityConfig.cxx`: configuración de los plugins de seguridad y validación de archivos.
- `security/xml/`: documentos de gobernanza y permisos (sin firmar).
- `generate_security_artifacts.sh`: generación de la PKI (RSA-2048) y firma S/MIME de los XML.
- `run_<escenario>.sh`: orquestación de las corridas de cada escenario.
- `monitor_recursos.sh`: captura de métricas en la Raspberry Pi.
- `results.ipynb`: procesamiento de datos y gráficas.
- `Dockerfile`: entorno reproducible basado en Ubuntu 22.04 y Fast DDS (ROS 2 Humble).
