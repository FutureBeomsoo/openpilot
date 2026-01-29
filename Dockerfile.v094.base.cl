# openpilot v0.9.4 Base Image with OpenCL
# Dockerfile.v094.base 기반 + Intel OpenCL 드라이버 + NVIDIA 지원
#
# 빌드: docker build -t openpilot-base-cl:v094 -f Dockerfile.v094.base.cl .

FROM openpilot-base:v094

# 추가 시스템 패키지
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    alien \
    unzip \
    tar \
    xz-utils \
    dbus \
    tmux \
    vim \
    lsb-core \
    libx11-6 \
  && rm -rf /var/lib/apt/lists/*

# Intel OpenCL 드라이버 설치
ARG INTEL_DRIVER=l_opencl_p_18.1.0.015.tgz
ARG INTEL_DRIVER_URL=https://registrationcenter-download.intel.com/akdlm/irc_nas/vcp/15532
RUN mkdir -p /tmp/opencl-driver-intel
WORKDIR /tmp/opencl-driver-intel
RUN echo "Installing Intel OpenCL driver: $INTEL_DRIVER" && \
    curl -O $INTEL_DRIVER_URL/$INTEL_DRIVER && \
    tar -xzf $INTEL_DRIVER && \
    for i in $(basename $INTEL_DRIVER .tgz)/rpm/*.rpm; do alien --to-deb $i; done && \
    dpkg -i *.deb && \
    rm -rf $INTEL_DRIVER $(basename $INTEL_DRIVER .tgz) *.deb && \
    mkdir -p /etc/OpenCL/vendors && \
    echo /opt/intel/opencl_compilers_and_libraries_18.1.0.015/linux/compiler/lib/intel64_lin/libintelocl.so > /etc/OpenCL/vendors/intel.icd && \
    rm -rf /tmp/opencl-driver-intel

# NVIDIA 환경 변수
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute
ENV QTWEBENGINE_DISABLE_SANDBOX=1

# D-Bus machine-id 생성
RUN dbus-uuidgen > /etc/machine-id

# tmux 설정 (NEOS 스타일)
RUN cd /root && \
    curl -O https://raw.githubusercontent.com/commaai/eon-neos-builder/master/devices/eon/home/.tmux.conf || true

WORKDIR /root/openpilot

CMD ["/bin/bash"]
