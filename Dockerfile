# 1. Imagen base (Ubuntu 22.04 LTS es la más estable para FastDDS)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 2. Instalar herramientas base esenciales
#    openssl     → CLI para ejecutar generate_security_artifacts.sh dentro del contenedor
#    libssl-dev  → Cabeceras de desarrollo OpenSSL requeridas por FastDDS Security
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    lsb-release \
    build-essential \
    cmake \
    git \
    libasio-dev \
    libtinyxml2-dev \
    openssl \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Configurar repositorio ROS 2 para obtener FastDDS oficial
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

# 4. Instalar librerías de FastDDS y FastCDR
RUN apt-get update && apt-get install -y \
    ros-humble-fastrtps \
    ros-humble-fastcdr \
    && rm -rf /var/lib/apt/lists/*

# 5. Configurar directorio de trabajo
WORKDIR /app

# 6. Copiar solo el código fuente (para que el build sea más rápido)
COPY . .

# 7. Generar los artefactos PKI y firmar los XML de seguridad DDS-Security.
#    El script crea security/pki/ y security/signed/ con todos los .pem y .p7s
#    necesarios para los escenarios auth, encrypt y access.
#    Si los artefactos ya están presentes en el contexto de build, este paso
#    los sobreescribirá con claves nuevas (comportamiento esperado en CI/CD).
RUN bash generate_security_artifacts.sh

# 8. Compilar el proyecto C++ usando las rutas de ROS
RUN rm -rf build && mkdir build && cd build && \
    cmake -DCMAKE_PREFIX_PATH=/opt/ros/humble .. && \
    make -j$(nproc)

# 9. Al ser manual, entramos directo a la terminal al arrancar.
#    Ejecutar siempre desde /app para que las rutas relativas a
#    security/pki/ y security/signed/ se resuelvan correctamente:
#       ./build/payload publisher 1000 1024 1000 auth
#       ./build/payload subscriber auth
CMD ["/bin/bash"]
