FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl qemu-system-x86 qemu-utils cloud-image-utils \
    openssh-client socat ttyd openssl procps iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/vm
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /data /run/qemu \
    && chmod 0777 /data

ENV PORT=8080 \
    VM_NAME=debian13 \
    VM_RAM=2048 \
    VM_CPUS=2 \
    VM_DISK_SIZE=20G \
    VM_USERNAME=sam \
    VM_PASSWORD=ChangeMe-Immediately \
    TTYD_USERNAME=sam \
    TTYD_PASSWORD=ChangeMe-Immediately

EXPOSE 8080 2222
VOLUME ["/data"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
