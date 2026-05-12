# bitdefender-gz-connector

Helm chart that deploys the **Bitdefender GravityZone Event Push Service
Connector** (`gz-evpsc`) on Kubernetes, configured to relay events as
CEF syslog to a Wazuh manager.

The connector is a Node.js HTTPS server that receives push events from
Bitdefender's Control Center cloud and forwards them via syslog (TCP or
UDP) to the destination of your choice — usually the Wazuh manager
service inside the cluster.

## Prerequisites

- Kubernetes ≥ 1.25
- Helm ≥ 3.10
- A reachable Wazuh manager configured to accept syslog from this
  workload (see the project root `README.md`).
- A Bitdefender API key (Control Center → My Account → API keys), and
  its `Basic <base64>` Authorization header.

## Install (HTTP repository)

```bash
helm repo add bitdefender-gz https://manustars.github.io/wazzuh-bitdefender-k8s
helm repo update

helm install gz bitdefender-gz/bitdefender-gz-connector \
  --namespace bitdefender --create-namespace \
  --set auth.value='Basic ZHVtbXk6ZHVtbXk=' \
  --set syslog.target=wazuh-manager.wazuh.svc.cluster.local
```

## Install (OCI)

```bash
helm install gz oci://ghcr.io/manustars/wazzuh-bitdefender-k8s/charts/bitdefender-gz-connector \
  --version 0.1.0 \
  --namespace bitdefender --create-namespace \
  --set auth.value='Basic ZHVtbXk6ZHVtbXk=' \
  --set syslog.target=wazuh-manager.wazuh.svc.cluster.local
```

## Production-grade install

Use cert-manager for TLS and an external Secret for the AUTH header:

```bash
# 1. Create the AUTH secret
kubectl -n bitdefender create secret generic gz-auth \
  --from-literal=auth='Basic ZHVtbXk6ZHVtbXk='

# 2. Provision a TLS cert with cert-manager that lands in `gz-tls` (omitted)

# 3. Install
helm install gz bitdefender-gz/bitdefender-gz-connector \
  --namespace bitdefender \
  --set auth.existingSecret.name=gz-auth \
  --set tls.mode=existingSecret \
  --set tls.existingSecret.name=gz-tls \
  --set syslog.target=wazuh-manager.wazuh.svc.cluster.local \
  --set service.type=LoadBalancer \
  --set 'service.loadBalancerSourceRanges={<bitdefender-cidr-1>,<bitdefender-cidr-2>}' \
  --set networkPolicy.enabled=true
```

## Values

See [values.yaml](values.yaml) — every key is documented inline and
validated by `values.schema.json` (`helm install` will fail fast on
invalid combinations).

## Uninstall

```bash
helm uninstall gz -n bitdefender
```

## Upgrading

This chart follows SemVer. Breaking changes are noted in the project
`CHANGELOG.md` and in `Chart.yaml`'s annotations.
