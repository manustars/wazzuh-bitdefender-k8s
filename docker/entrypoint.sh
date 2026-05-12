#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Bitdefender GravityZone EVPSC — container entrypoint
#
# Responsibilities:
#   1. Resolve runtime secrets (AUTH from env or AUTH_FILE).
#   2. Materialise / locate the TLS material used for the inbound HTTPS API
#      (either provided via a mounted Secret or self-generated for dev/test).
#   3. Render the connector config.json into a writable runtime directory.
#   4. Hand off to `node server.js` as PID 2 (tini is PID 1).
#
# Configuration is taken entirely from environment variables — never write
# secrets into the image.
# ----------------------------------------------------------------------------
set -Eeuo pipefail

log()  { printf '[entrypoint] %s\n' "$*" >&2; }
die()  { log "FATAL: $*"; exit 1; }

# --------------------------------------------------------------------------- #
# 1. Required configuration                                                   #
# --------------------------------------------------------------------------- #
: "${GZ_EVPSC_HOME:?GZ_EVPSC_HOME must be set (set in the Dockerfile)}"
: "${GZ_EVPSC_RUNTIME_DIR:?GZ_EVPSC_RUNTIME_DIR must be set (set in the Dockerfile)}"
: "${BITDEFENDER_PORT:=3200}"
: "${SYSLOG_PORT:=514}"
: "${TRANSPORT:=Tcp}"

if [[ -z "${TARGET:-}" ]]; then
    die "TARGET env var is required (syslog destination — typically the Wazuh manager service)"
fi

case "${TRANSPORT}" in
    Tcp|Udp) ;;
    *) die "TRANSPORT must be 'Tcp' or 'Udp' (got: '${TRANSPORT}')" ;;
esac

# --------------------------------------------------------------------------- #
# 2. AUTH header (Basic <base64>) — prefer file (mounted Secret) over env     #
# --------------------------------------------------------------------------- #
if [[ -n "${AUTH_FILE:-}" ]]; then
    [[ -r "${AUTH_FILE}" ]] || die "AUTH_FILE='${AUTH_FILE}' is not readable"
    AUTH="$(tr -d '\r\n' < "${AUTH_FILE}")"
fi
if [[ -z "${AUTH:-}" ]]; then
    die "AUTH (or AUTH_FILE) is required — must contain the full Authorization header (e.g. 'Basic <base64>')"
fi
# Make sure callers always see a fully-formed Authorization header. The upstream
# blog example uses 'Basic <base64>' — if the caller passed only the base64
# payload we transparently add the 'Basic ' prefix.
if [[ "${AUTH}" != Basic\ * && "${AUTH}" != Bearer\ * ]]; then
    AUTH="Basic ${AUTH}"
fi

# --------------------------------------------------------------------------- #
# 3. TLS material                                                             #
# --------------------------------------------------------------------------- #
RUNTIME_KEY="${GZ_EVPSC_RUNTIME_DIR}/server.key"
RUNTIME_CRT="${GZ_EVPSC_RUNTIME_DIR}/server.crt"

mkdir -p "${GZ_EVPSC_RUNTIME_DIR}"

if [[ -n "${TLS_KEY_PATH:-}" || -n "${TLS_CERT_PATH:-}" ]]; then
    [[ -r "${TLS_KEY_PATH:-}"  ]] || die "TLS_KEY_PATH='${TLS_KEY_PATH:-}' is not readable"
    [[ -r "${TLS_CERT_PATH:-}" ]] || die "TLS_CERT_PATH='${TLS_CERT_PATH:-}' is not readable"
    log "Using mounted TLS material: key=${TLS_KEY_PATH} cert=${TLS_CERT_PATH}"
    EFFECTIVE_KEY="${TLS_KEY_PATH}"
    EFFECTIVE_CRT="${TLS_CERT_PATH}"
elif [[ -s "${RUNTIME_KEY}" && -s "${RUNTIME_CRT}" ]]; then
    log "Reusing TLS material previously generated at ${GZ_EVPSC_RUNTIME_DIR}"
    EFFECTIVE_KEY="${RUNTIME_KEY}"
    EFFECTIVE_CRT="${RUNTIME_CRT}"
else
    log "No TLS material provided — generating a self-signed certificate (DEV/TEST only)"
    log "       For production, mount a Kubernetes TLS Secret and set TLS_KEY_PATH / TLS_CERT_PATH."
    openssl req -new -newkey rsa:4096 -x509 -nodes -days 3650 \
        -keyout "${RUNTIME_KEY}" \
        -out    "${RUNTIME_CRT}" \
        -subj   '/CN=gz-evpsc' \
        2>/dev/null
    chmod 0600 "${RUNTIME_KEY}"
    EFFECTIVE_KEY="${RUNTIME_KEY}"
    EFFECTIVE_CRT="${RUNTIME_CRT}"
fi

# --------------------------------------------------------------------------- #
# 4. Render config.json                                                       #
# --------------------------------------------------------------------------- #
CONFIG_FILE="${GZ_EVPSC_RUNTIME_DIR}/config.json"

# server.js resolves relative paths against its own __dirname (i.e. the app
# home), so the key / cert paths must be absolute when they live outside the
# app dir.
cat >"${CONFIG_FILE}" <<JSON
{
    "port": ${BITDEFENDER_PORT},
    "syslog_port": ${SYSLOG_PORT},
    "transport": "${TRANSPORT}",
    "target": "${TARGET}",
    "authentication_string": "${AUTH}",
    "secure": {
        "enabled": true,
        "key": "${EFFECTIVE_KEY}",
        "cert": "${EFFECTIVE_CRT}"
    }
}
JSON
chmod 0600 "${CONFIG_FILE}"

log "Starting gz-evpsc — target=${TARGET}:${SYSLOG_PORT}/${TRANSPORT}, inbound HTTPS on :${BITDEFENDER_PORT}"

# --------------------------------------------------------------------------- #
# 5. Hand off to Node                                                         #
# --------------------------------------------------------------------------- #
cd "${GZ_EVPSC_HOME}"

# If we somehow ended up as root (e.g. the orchestrator overrode USER), step
# down to the unprivileged uid. In Kubernetes the SecurityContext should make
# this branch unreachable.
if [[ "$(id -u)" == "0" ]]; then
    chown -R evpsc:evpsc "${GZ_EVPSC_RUNTIME_DIR}"
    exec gosu evpsc:evpsc /usr/local/bin/node --trace-warnings server.js "${CONFIG_FILE}"
fi

exec /usr/local/bin/node --trace-warnings server.js "${CONFIG_FILE}"
