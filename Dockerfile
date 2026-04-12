# 1. Imagen base
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 2. OPTIMIZACIÓN DE CAPAS: Combinamos herramientas base, repo ROS 2 y FastDDS
# Se usa --no-install-recommends para evitar paquetes innecesarios y rm -rf para limpiar
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
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
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-fastrtps \
    ros-humble-fastcdr \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 3. Configurar directorio de trabajo
WORKDIR /app

# 4. MEJORA DE SEGURIDAD: Usuario no-root
# Creamos un usuario para ejecutar las pruebas sin privilegios de administrador
RUN useradd -m -s /bin/bash ddsuser && \
    chown -R ddsuser:ddsuser /app

# 5. Copiar código fuente
COPY --chown=ddsuser:ddsuser . .

# Cambiamos al usuario creado
USER ddsuser

# 6. Generar artefactos PKI y compilar
# Combinamos la generación y compilación para mantener la coherencia
RUN bash generate_security_artifacts.sh && \
    rm -rf build && mkdir build && cd build && \
    cmake -DCMAKE_PREFIX_PATH=/opt/ros/humble .. && \
    make -j$(nproc)

# 7. Ejecución
CMD ["/bin/bash"]
