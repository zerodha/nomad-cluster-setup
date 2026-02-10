# Changelog

All notable changes to this project will be documented in this file.

## [v1.5.0](https://github.com/zerodha/nomad-cluster-setup/releases/tag/v1.5.0) - 2026-02-10

### Features

- **Garbage collection configuration** — Make GC intervals and thresholds configurable for jobs, deployments, evaluations, and nodes ([#34](https://github.com/zerodha/nomad-cluster-setup/pull/34)) by @codingCoffee
- **HTTP max connections per client** — Add `http_max_conns_per_client` variable to control the maximum number of concurrent HTTP connections from a single client ([#33](https://github.com/zerodha/nomad-cluster-setup/pull/33)) by @codingCoffee
- **mTLS support** — Add support for enabling mutual TLS (mTLS) for Nomad cluster communication, including `verify_https_client` configuration ([#32](https://github.com/zerodha/nomad-cluster-setup/pull/32)) by @codingCoffee
- **Raft snapshot backup to S3** — Add support to automatically backup Nomad raft snapshots to an S3 bucket ([#31](https://github.com/zerodha/nomad-cluster-setup/pull/31)) by @codingCoffee
- **Memory oversubscription** — Allow enabling memory oversubscription in the Nomad cluster with simplified configuration logic ([#30](https://github.com/zerodha/nomad-cluster-setup/pull/30)) by @codingCoffee

### Changed

- Set `verify_https_client` automatically based on `tls_http_enable` flag

**Full Changelog**: https://github.com/zerodha/nomad-cluster-setup/compare/v1.4.0...v1.5.0

---

## [v1.4.0](https://github.com/zerodha/nomad-cluster-setup/releases/tag/v1.4.0) - 2025-12-03

### What's Changed

- EC2 tags support ([#28](https://github.com/zerodha/nomad-cluster-setup/pull/28)) by @codingCoffee
- Security group fixes ([#27](https://github.com/zerodha/nomad-cluster-setup/pull/27)) by @codingCoffee

**Full Changelog**: https://github.com/zerodha/nomad-cluster-setup/compare/v1.3.0...v1.4.0

---

## [v1.3.0](https://github.com/zerodha/nomad-cluster-setup/releases/tag/v1.3.0) - 2025-11-12

### What's Changed

- fix: allow sed to follow symlinks ([#26](https://github.com/zerodha/nomad-cluster-setup/pull/26)) by @cvhariharan

**Full Changelog**: https://github.com/zerodha/nomad-cluster-setup/compare/v1.2.0...v1.3.0

---

## [v1.2.0](https://github.com/zerodha/nomad-cluster-setup/releases/tag/v1.2.0) - 2025-05-27

**Full Changelog**: https://github.com/zerodha/nomad-cluster-setup/compare/v1.1.11...v1.2.0

---

## [v1.1.11](https://github.com/zerodha/nomad-cluster-setup/releases/tag/v1.1.11) - 2024-07-13

**Full Changelog**: https://github.com/zerodha/nomad-cluster-setup/compare/v1.1.10...v1.1.11
