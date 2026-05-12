# wazzuh-bitdefender-k8s

Production-ready container image and Helm chart that bring the **Bitdefender
GravityZone Event Push Service Connector** (`gz-evpsc`) into Kubernetes and
relay events as CEF syslog to a **Wazuh** manager.

Based on the official Wazuh integration guide:
<https://wazuh.com/blog/integrating-bitdefender-gravityzone-with-wazuh/>

---

## What you get

| Component         | Where it lives                                                       |
| ----------------- | -------------------------------------------------------------------- |
| Container image   | `ghcr.io/manustars/wazzuh-bitdefender-k8s/bitdefender-gz-connector`  |
| Helm chart (HTTP) | `https://manustars.github.io/wazzuh-bitdefender-k8s`                 |
| Helm chart (OCI)  | `oci://ghcr.io/manustars/wazzuh-bitdefender-k8s/charts/bitdefender-gz-connector` |
| Wazuh decoder     | [`wazuh/decoders/bitdefendergz.xml`](wazuh/decoders/bitdefendergz.xml) |
| Wazuh rules       | [`wazuh/rules/bitdefender.xml`](wazuh/rules/bitdefender.xml)         |

### Key properties

- **Multi-arch image** (`linux/amd64`, `linux/arm64`). The upstream
  `gz-evpsc` package is pure Node.js (`Architecture: all`), so the
  connector itself is portable. The Dockerfile selects the matching
  Node.js base image at build time via Buildx.
- **Hardened runtime**: distroless-style — runs as UID 10001, read-only
  root filesystem, `cap_drop=ALL`, `runAsNonRoot=true`, seccomp
  `RuntimeDefault`, `automountServiceAccountToken=false`.
- **Supply-chain hygiene**: pinned upstream `.deb` SHA-256, SBOM (SPDX)
  attached to the image, SLSA provenance, cosign keyless signatures on
  both the image and the published chart OCI artefact.
- **Helm chart best practices**: `values.schema.json`, standard
  `app.kubernetes.io/*` labels, NetworkPolicy, PodDisruptionBudget,
  topology spread, configurable TLS (self-signed or
  `kubernetes.io/tls` Secret), AUTH from existing Secret, Helm test
  hook.

---

## How it fits together

```
                                           ┌──────────────────────────────┐
                                           │  Bitdefender GravityZone     │
                                           │  Control Center (cloud)      │
                                           └──────────────┬───────────────┘
                                                          │  HTTPS push (POST /api)
                                                          │  Basic <base64> auth
                                                          ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ Kubernetes cluster                                                            │
│                                                                               │
│   ┌──────────────────────────┐         ┌──────────────────────────────────┐   │
│   │ Service (LoadBalancer or │ ──────► │ Deployment: gz-evpsc connector   │   │
│   │ NodePort) :3200/HTTPS    │         │   Node.js HTTPS → syslog client  │   │
│   └──────────────────────────┘         └──────────────┬───────────────────┘   │
│                                                       │ syslog/TCP|UDP        │
│                                                       ▼                       │
│                                       ┌──────────────────────────────────┐   │
│                                       │ wazuh-manager  (decodes CEF →    │   │
│                                       │  alerts via rules 100600/100601) │   │
│                                       └──────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## Deploying

### 1. Prepare the Wazuh manager

On the Wazuh manager, drop the decoder + rules in place and reload:

```bash
sudo cp wazuh/decoders/bitdefendergz.xml /var/ossec/etc/decoders/
sudo cp wazuh/rules/bitdefender.xml     /var/ossec/etc/rules/
# Add or merge wazuh/ossec.conf.snippet.xml into /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-manager
```

Make sure the manager's `<remote>` block listens on the syslog port you
will point the connector at (default `514/tcp`) and that the
`<allowed-ips>` range covers either your pod CIDR (if running in the
same cluster as Wazuh) or the Kubernetes egress IP.

### 2. Get a Bitdefender API key

In GravityZone Control Center: **My Account → API keys → Add → Event Push Service API**.
Then base64-encode it for the connector's Basic auth:

```bash
echo -n "<BITDEFENDER_API_KEY>:" | base64 -w 0
# → e.g. ZHVtbXk6dGVzdA==
```

You will use it as `Basic ZHVtbXk6dGVzdA==`.

### 3. Install the chart

Quick, single-command install (HTTP repo):

```bash
helm repo add bitdefender-gz https://manustars.github.io/wazzuh-bitdefender-k8s
helm repo update

helm install gz bitdefender-gz/bitdefender-gz-connector \
  --namespace bitdefender --create-namespace \
  --set auth.value='Basic ZHVtbXk6dGVzdA==' \
  --set syslog.target=wazuh-manager.wazuh.svc.cluster.local \
  --set service.type=LoadBalancer
```

Production-grade install (external Secret for AUTH, real TLS, network
restrictions):

```bash
# AUTH from a Secret you manage out-of-band
kubectl -n bitdefender create secret generic gz-auth \
  --from-literal=auth='Basic ZHVtbXk6dGVzdA=='

# TLS cert via cert-manager (produces Secret 'gz-tls' of type kubernetes.io/tls)
# Example Certificate resource omitted; use the issuer of your choice.

helm install gz bitdefender-gz/bitdefender-gz-connector \
  --namespace bitdefender \
  --set auth.existingSecret.name=gz-auth \
  --set tls.mode=existingSecret \
  --set tls.existingSecret.name=gz-tls \
  --set syslog.target=wazuh-manager.wazuh.svc.cluster.local \
  --set service.type=LoadBalancer \
  --set-string 'service.loadBalancerSourceRanges={203.0.113.0/24,198.51.100.0/24}' \
  --set networkPolicy.enabled=true \
  --set podDisruptionBudget.enabled=true
```

Then point Bitdefender's **Push event configuration** URL at the
external address of the service:

```
https://<external-host>:3200/api
```

…with the same `Authorization` header you set in `auth`.

### 4. Verify

```bash
kubectl -n bitdefender logs -l app.kubernetes.io/name=bitdefender-gz-connector -f
helm test gz -n bitdefender
```

On the Wazuh manager:

```bash
cat /var/ossec/logs/alerts/alerts.log | grep -i bitdefender
```

---

## Versioning

- **Image**: tagged with SemVer (`vX.Y.Z`, `X.Y`, `X`, plus
  `latest` for the most recent stable release and `edge` for the
  current default branch). PRs build but do not push.
- **Chart**: bumped by editing `charts/bitdefender-gz-connector/Chart.yaml`.
  `chart-releaser` detects the new `version` on push to the default
  branch and publishes a GitHub Release + repo-index update on
  `gh-pages`, plus an OCI artefact in GHCR.
- **Upstream `gz-evpsc`**: pinned via `GZ_EVPSC_VERSION` +
  `GZ_EVPSC_SHA256` build args in `docker/Dockerfile`. Bumping these
  also bumps the chart's `appVersion`.

---

## Repository layout

```
.
├── .github/workflows/
│   ├── ci.yml                  # hadolint, shellcheck, ct lint, kubeconform
│   ├── docker-publish.yml      # multi-arch image build + push + sign + scan
│   └── helm-release.yml        # chart-releaser to gh-pages + OCI push + sign
├── charts/
│   └── bitdefender-gz-connector/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       └── templates/
├── docker/
│   ├── Dockerfile              # multi-stage, multi-arch
│   └── entrypoint.sh           # config rendering + handoff to node
├── wazuh/
│   ├── decoders/bitdefendergz.xml
│   ├── rules/bitdefender.xml
│   └── ossec.conf.snippet.xml
├── CHANGELOG.md
├── LICENSE
└── README.md (this file)
```

---

## One-time GitHub setup

After the first `git push`, in the repository on GitHub:

1. **Settings → Actions → General → Workflow permissions**: set to
   *Read and write permissions* (chart-releaser pushes commits to
   `gh-pages`).
2. **Settings → Pages**: source = *Deploy from a branch*, branch =
   `gh-pages`, folder = `/ (root)`. The first run of the helm-release
   workflow will create this branch.
3. **Settings → Packages → bitdefender-gz-connector**: set the package
   visibility to **Public** (otherwise `helm pull` from CI / consumers
   will need credentials).
4. **Settings → Actions → General → Allow GitHub Actions to create and
   approve pull requests** can stay off.

The cosign signatures use OIDC keyless signing (no secrets to manage).

---

## License

MIT — see [`LICENSE`](LICENSE). Note that the upstream `gz-evpsc`
binary remains the property of Bitdefender SRL and is redistributed
from its official APT repository at build time.
