#!/bin/bash

########################################################################
##                    Global Variables                                ##
########################################################################

# Logging
LOG_INFO_COLOR="\033[0;36m"
LOG_ERROR_COLOR="\033[1;91m"
LOG_CMD_COLOR="\033[0m"

# Paths
MAIN_DIR="/home/ceadmin/docker-generation-scripts/petalinux"
SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
WORKING_DIR=tmp-${SUFFIX}
INSTALLERS_DIR="/home/ceadmin/docker-generation-scripts/petalinux/installers"

# Image
OUTPUT_IMAGE_NAME="petalinux"

########################################################################
##                    Usage Functions                                 ##
########################################################################

usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  versions                  List available PetaLinux versions."
    echo "  build                     Build PetaLinux version with specified version."
    echo ""
    echo "Build Options:"
    echo "  -v, --version VERSION     Specify the PetaLinux version to use (e.g. v2021.1)."
    echo ""
    echo "Examples:"
    echo "  List available PetaLinux versions:"
    echo "    $0 versions"
    echo ""
    echo "  Build PetaLinux 2024.1 Docker image:"
    echo "    $0 build -v v2024.1"
}

########################################################################
##                    Util Functions                                  ##
########################################################################


log() {
 local level="$1"
 local msg="$2"
 local ts=$(date -u)  

 if [ "$level" == "error" ]; then
   echo -e "${LOG_ERROR_COLOR}:${ts}:${level}: ${msg} ${LOG_CMD_COLOR}"
 elif [ "$level" == "info" ]; then
   echo -e "${LOG_INFO_COLOR}:${ts}:${level}: ${msg} ${LOG_CMD_COLOR}"
 fi
}

list_petalinux_versions() {
  versions=$(ls -l ${INSTALLERS_DIR} | awk -F' ' '{print $9}' | awk -F'-' '{print $2}' | sed '/^$/d')
  echo "$versions"
}

cleanup() {
  log "info" "Deleting tmp directory..."
  cd ${MAIN_DIR}
  rm -rf ${WORKING_DIR}
}


generate_dockerfile() {
  local version="$1"
  local new_dockerfile_path="${WORKING_DIR}/Dockerfile"
  local installer_file=$(ls -l ${INSTALLERS_DIR} | awk -F' ' '{print $9}' | sed '/^$/d' | grep "$version")
  log "info" "$installer_file"

  log "info" "Generating Dockerfile..."

  mkdir -p "${WORKING_DIR}"
  cp ${INSTALLERS_DIR}/${installer_file} ${WORKING_DIR}

  local from_line="FROM ubuntu:22.04"
  
  local arg_lines="ARG DEBIAN_FRONTEND=noninteractive
  ARG TZ=Asia/Jerusalem
  ARG INSTALLER_FILE=${installer_file}"

  local run_deps_line="RUN dpkg --add-architecture i386 \
    && dpkg-reconfigure -f noninteractive dash \
    && apt-get update \
    && apt-get install -y \
        sudo \
        vim \
        nano \
        xfce4-terminal \
        byobu \
        wget \
        curl \
        bc \
        rsync \
        iproute2 \
        make \
        libncurses5-dev \
        tftpd \
        libselinux1 \
        wget \
        diffstat \
        chrpath \
        socat \
        tar \
        unzip \
        gzip \
        tofrodos \
        debianutils \
        iputils-ping \
        libegl1-mesa \
        libsdl1.2-dev \
        pylint \
        python3 \
        python2 \
        cpio \
        tftpd \
        gnupg \
        zlib1g:i386 \
        haveged \
        perl \
        lib32stdc++6 \
        libgtk2.0-0:i386 \
        libfontconfig1:i386 \
        libx11-6:i386 \
        libxext6:i386 \
        libxrender1:i386 \
        libsm6:i386 \
        xinetd \
        gawk \
        gcc \
        net-tools \
        ncurses-dev \
        openssl \
        libssl-dev \
        flex \
        bison \
        xterm \
        autoconf \
        libtool \
        texinfo \
        zlib1g-dev \
        cpp-11 \
        patch \
        diffutils \
        gcc-multilib \
        build-essential \
        automake \
        screen \
        putty \
        pax \
        g++ \
        python3-pip \
        xz-utils \
        python3-git \
        python3-jinja2 \
        python3-pexpect \
        liberror-perl \
        mtd-utils \
        xtrans-dev \
        libxcb-randr0-dev \
        libxcb-xtest0-dev \
        libxcb-xinerama0-dev \
        libxcb-shape0-dev \
        libxcb-xkb-dev \
        openssh-server \
        util-linux \
        sysvinit-utils \
        google-perftools \
        libncurses5 \
        libncurses5-dev \
        libncursesw5-dev \
        libncurses5:i386 \
        libtinfo5 \
        libstdc++6:i386 \
        libgtk2.0-0:i386 \
        dpkg-dev:i386 \
        ocl-icd-libopencl1 \
        opencl-headers \
        ocl-icd-opencl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*"

  local run_usr_line="RUN adduser --disabled-password --gecos '' petalinux \
  && usermod -aG sudo petalinux \
  && echo 'petalinux ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
  && mkdir -p /opt/PetaLinux/${version} \
  && chown -R petalinux:petalinux /opt/PetaLinux/ 
  USER petalinux"

  local copy_line="COPY --chmod=755 ./${installer_file} /home/petalinux/${installer_file}"
  
  local petalinux_install_line="RUN cd /home/petalinux/ \
  && ./${installer_file} -d /opt/PetaLinux/${version} --skip_license"

  local entrypoint_line="CMD source /opt/PetaLinux/${version}/settings.sh"

  local docker_context="$from_line
  $arg_lines
  $run_deps_line
  $run_usr_line
  $copy_line
  $petalinux_install_line"

  echo "${docker_context}" | sed 's/^[ \t]*//' | sed 's/\"//g' > "${new_dockerfile_path}"
  printf "%s" "${new_dockerfile_path}"
}

build_docker() {
    local build_path="$1"
    local is_buildx="true"
    local full_image_name="${OUTPUT_IMAGE_NAME}:${petalinux_version}"
    
    echo "******************************************"
    echo "$full_image_name"
    log "info" "Building Docker Image..."
    
    if ! docker buildx version > /dev/null 2>&1; then
      log "info" "Docker buildx is not installed on this host, using docker build."
      is_buildx="false"
    fi

    cd ${WORKING_DIR}

    if [[ is_buildx == "true" ]]; then
      docker buildx build -t ${full_image_name} .
    else
      docker build -t ${full_image_name} .
    fi

    if [[ $? != 0 ]]; then
      log "error" "Failed to build Docker Image."
      rm -rf ${WORKING_DIR}
      exit 1
    else
      log "info" "New Docker Image is available: ${full_image_name}."
    fi

    cd ..

    log "info" "To run new container use: docker run -it --rm --name petalinux ${full_image_name}"
    log "info" "To activate PetaLinux run: source /opt/PetaLinux/${petalinux_version}/settings.sh"
}

########################################################################
##                    Trap SIGINT                                     ##
########################################################################

trap cleanup SIGINT

########################################################################
##                    Build Docker CMD                                ##
########################################################################

if [ "$1" == "build" ]; then
  shift 1
  TEMP=$(getopt -o v: --long version: -n "$0" -- "$@")
  if [ $? != 0 ]; then
    log "error" "Failed to parse options."
    exit 1
  fi

  eval set -- "$TEMP"

  while true; do
    case "$1" in
      -v|--version)
        petalinux_version="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        usage
        ;;
    esac
  done

  if ! echo "$petalinux_version" | grep -qE '^v[0-9]{4}.[0-9]{1}$'; then
    log "error" "Version should be in format 'v[2019-2024].[1-3]', for example v2022.1"
    exit 1
  fi

  versions=$(list_petalinux_versions)
  if ! echo "$versions" | grep -q "$petalinux_version"; then
    log "error" "Version not exist in list, please choose one of the versions below:"
    echo "$versions"
    exit 1
  fi
  
  build_path=$(generate_dockerfile "$petalinux_version")
  
  build_docker "$build_path"
  
  rm -rf ${WORKING_DIR}  

########################################################################
##                    List Versions CMD                               ##
########################################################################

elif [ "$1" == "versions" ]; then
  shift 1
  log "info" "Choose PetaLinux version from the available options:"
  versions=$(list_petalinux_versions)
  echo "$versions"

########################################################################
##                    No CMD                                          ##
########################################################################

else
  usage
fi
