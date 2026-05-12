# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-12

### Added
- Multi-arch container image (`linux/amd64`, `linux/arm64`) packaging
  the upstream Bitdefender `gz-evpsc 1.0.0-4` Node.js connector.
- Hardened runtime: non-root UID 10001, read-only root filesystem,
  dropped capabilities, seccomp `RuntimeDefault`.
- Helm chart `bitdefender-gz-connector` v0.1.0 with `values.schema.json`,
  optional NetworkPolicy / PodDisruptionBudget, TLS via existing Secret
  or self-signed, AUTH via inline value or existing Secret.
- GitHub Actions: image build & push (multi-arch, SBOM, cosign sign,
  Trivy scan, SLSA provenance); chart release via chart-releaser
  (gh-pages) + GHCR OCI; lint pipeline (hadolint, shellcheck, ct lint,
  kubeconform).
- Wazuh decoder, rules and `ossec.conf` snippet for CEF-formatted
  Bitdefender GravityZone events.

[Unreleased]: https://github.com/Manustars/wazzuh-bitdefender-k8s/compare/v0.1.0...HEAD
[0.1.0]:      https://github.com/Manustars/wazzuh-bitdefender-k8s/releases/tag/v0.1.0
