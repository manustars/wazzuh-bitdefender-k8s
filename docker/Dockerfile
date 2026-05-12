# syntax=docker/dockerfile:1.7

# ------------------------------------------------------------------------------
# Bitdefender GravityZone EVPSC (Event Push Service Connector) — container image
#
# Upstream package (gz-evpsc) is a pure Node.js application distributed as a
# Debian package with Architecture: all. We extract it in a builder stage and
# copy the application files into a slim Node.js runtime. The image therefore
# supports every architecture for which an upstream node:*-bookworm-slim image
# exists (linux/amd64, linux/arm64, linux/arm/v7, ...).
# ------------------------------------------------------------------------------

ARG NODE_VERSION=20.18.1
ARG GZ_EVPSC_VERSION=1.0.0-4
# SHA256 of gz-evpsc_1.0.0-4_all.deb (pinned for supply-chain integrity)
ARG GZ_EVPSC_SHA256=91ce78d028eca0f73f7bb58bc8cca4d1c912542f2d6d58b6c1e20b446bd8976e

# ============================================================================
# Stage 1 — fetch & verify the upstream .deb, then extract the application
# ============================================================================
FROM debian:bookworm-slim AS extractor

ARG GZ_EVPSC_VERSION
ARG GZ_EVPSC_SHA256

SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        binutils \
        xz-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN curl -fsSL -o gz-evpsc.deb \
        "https://download.bitdefender.com/repos/deb-hydra20-evpsc/pool/non-free/g/gz-evpsc/gz-evpsc_${GZ_EVPSC_VERSION}_all.deb" \
 && echo "${GZ_EVPSC_SHA256}  gz-evpsc.deb" | sha256sum -c - \
 && ar x gz-evpsc.deb \
 && mkdir rootfs \
 && tar -C rootfs -xf data.tar.xz \
 && test -f rootfs/opt/bitdefender/gz-evpsc/server.js \
 && test -d rootfs/opt/bitdefender/gz-evpsc/node_modules \
 && rm -f gz-evpsc.deb data.tar.xz control.tar.* debian-binary

# ============================================================================
# Stage 2 — runtime
# ============================================================================
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG GZ_EVPSC_VERSION

# OCI image annotations — populated by CI at build time
ARG IMAGE_TITLE="bitdefender-gz-connector"
ARG IMAGE_DESCRIPTION="Bitdefender GravityZone Event Push Service Connector for Wazuh"
ARG IMAGE_VENDOR="Manustars"
ARG IMAGE_SOURCE="https://github.com/Manustars/wazzuh-bitdefender-k8s"
ARG IMAGE_LICENSES="MIT"
ARG IMAGE_REVISION=""
ARG IMAGE_VERSION=""
ARG IMAGE_CREATED=""

LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
      org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
      org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.licenses="${IMAGE_LICENSES}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      io.gz-evpsc.upstream-version="${GZ_EVPSC_VERSION}"

SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# openssl: only needed at first start if a self-signed cert is generated.
# tini: PID-1 reaper / signal forwarder so node receives SIGTERM cleanly.
# gosu: drop privileges from root to the unprivileged user (only used in the
#       entrypoint when the container is started as root, e.g. on platforms
#       where the user cannot be specified).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        openssl \
        tini \
        gosu \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 evpsc \
 && useradd  --system --uid 10001 --gid 10001 \
        --home-dir /opt/bitdefender/gz-evpsc \
        --shell /usr/sbin/nologin \
        evpsc

# Application files from the extractor stage (no node_modules install required:
# upstream ships them already).
COPY --from=extractor --chown=root:root /work/rootfs/opt/bitdefender/gz-evpsc /opt/bitdefender/gz-evpsc

# Entrypoint
COPY --chown=root:root docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && chmod 0755 /opt/bitdefender/gz-evpsc/config.sh /opt/bitdefender/gz-evpsc/gen_cert.sh \
 && mkdir -p /var/lib/gz-evpsc \
 && chown -R evpsc:evpsc /var/lib/gz-evpsc

# Default values — every one of these can (and should) be overridden at runtime
# either via env (Helm `extraEnv`) or, for secrets, via *_FILE pointing to a
# mounted file.
ENV NODE_ENV=production \
    GZ_EVPSC_HOME=/opt/bitdefender/gz-evpsc \
    GZ_EVPSC_RUNTIME_DIR=/var/lib/gz-evpsc \
    BITDEFENDER_PORT=3200 \
    SYSLOG_PORT=514 \
    TRANSPORT=Tcp \
    TLS_KEY_PATH= \
    TLS_CERT_PATH= \
    AUTH_FILE= \
    AUTH= \
    TARGET=

WORKDIR /opt/bitdefender/gz-evpsc

# Drop privileges to the unprivileged user. Kubernetes SecurityContext should
# also set runAsUser/runAsGroup/runAsNonRoot=true (see Helm chart).
USER 10001:10001

EXPOSE 3200/tcp

# Basic in-image liveness check — Kubernetes will use its own probe, but this
# is useful when running the image with `docker run` directly.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "require('net').connect({host:'127.0.0.1',port:process.env.BITDEFENDER_PORT||3200}).on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
