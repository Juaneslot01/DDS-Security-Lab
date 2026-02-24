FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Instalación de dependencias y configuración de repositorios de ROS 2 (donde vive Fast DDS)
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    openjdk-17-jre \
    libfastrtps-dev \
    fastddsgen \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
