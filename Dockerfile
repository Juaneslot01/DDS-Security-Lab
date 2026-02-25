# 1. Imagen base (Ubuntu 22.04 LTS es la más estable para FastDDS)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 2. Instalar herramientas base esenciales
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    lsb-release \
    build-essential \
    cmake \
    git \
    libasio-dev \
    libtinyxml2-dev \
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

# 7. Compilar el proyecto C++ usando las rutas de ROS
RUN rm -rf build && mkdir build && cd build && \
    cmake -DCMAKE_PREFIX_PATH=/opt/ros/humble .. && \
    make -j$(nproc)

# 8. Al ser manual, entramos directo a la terminal al arrancar
CMD ["/bin/bash"]
