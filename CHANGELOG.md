# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

Targets immutable images, such as bootc images with a read-only `/usr`, and Nomad 2.x. The generated configuration is validated against Nomad 2.1.1.

### Breaking changes

- Secrets are read from SSM Parameter Store at boot instead of Terraform inputs. The new required `secrets_ssm_prefix` input replaces `nomad_gossip_encrypt_key`, `nomad_acl_bootstrap_token` and `tls_certificates`. Secrets no longer appear in user data, the launch template or Terraform state.
- `enable_tls` is renamed to `tls_enabled`, and `default_iam_policies` to `iam_policy_arns`.
- `aws_region` is removed. The region comes from the AWS provider.
- nomad-servers: `nomad_bootstrap_expect` is removed. `bootstrap_expect` now equals `instance_count`.
- nomad-clients: `ssh_user` and `ssh_public_keys` are removed. Manage access with cloud-init or SSM Session Manager.
- `http_tokens` defaults to `required` and `http_put_response_hop_limit` to `1`. Containers on bridge networks can no longer reach the instance credentials.
- The agent configuration is split into `/etc/nomad.d/{base,server|client,tls,secrets}.hcl`, and the packaged `/etc/nomad.d/nomad.hcl` is removed.
- The hostname is no longer rewritten from the `Name` tag.
- nomad-clients: the `ec2_*` node meta is built from the tags the module sets (`cluster_tags`, `ec2_tags`, `role`, `nomad_client`, `nomad_ec2_join`) instead of instance metadata. `ec2_Name` and `ec2_aws_*` keys are gone, and instances no longer need a `nomad-cluster` tag to boot.
- nomad-clients: host volume paths may only contain letters, digits, `_`, `.`, `-` and `/`.
- Agents leave the cluster gracefully when stopped (`leave_on_interrupt` and `leave_on_terminate`).
- Images need Nomad 1.7 or later and the AWS CLI v2.
- nomad-clients: the `ec2` client mode is removed, with the `client_type` and `ec2_count` inputs and the `nomad_client_ec2` and `nomad_client_ec2_availability_zones` outputs. Migration: size the ASG with `instance_*_count`, and remove `aws_instance.nomad_client` from state first if the old instances must survive the apply.
- nomad-clients: the unused `vpc` input is removed. Migration: delete it from the module call.
- `cluster_name` no longer needs a `-nomad` suffix. It must be 1-28 lowercase letters, digits or hyphens that start and end with a letter or digit, and in nomad-clients `<cluster_name>-<client_name>` must fit in 64 characters. Migration: shorten or lowercase names that fail; renaming replaces the named resources.
- The `packer/` template is removed. Migration: build an image that meets the [AMI](./README.md#ami) requirements.
- nomad-clients: `raw_exec` and privileged Docker tasks are off by default. Set `enable_raw_exec = true` or `docker_allow_privileged = true` to keep jobs that use them working. Both give tasks root on the host.

### Features

- `nomad_region` and `nomad_datacenter` inputs. The datacenter still defaults to `cluster_name`.
- An inline instance policy grants read access to `<secrets_ssm_prefix>/*`, `kms:Decrypt` through SSM (optionally limited to `kms_key_arn`), and the EC2 calls that cloud auto-join needs.
- nomad-clients: `node_pool` input, and `drain_on_shutdown` with a `drain_deadline` input (default `5m`).

### Fixes

- The Nomad unit is tuned with a systemd drop-in instead of `sed -i` on the packaged unit, which failed on a read-only `/usr`. The client's file limit check, which always passed, is gone.
- The advertise address uses the private IP of the default route interface instead of a hardcoded `ens5`.
- The launch template uses the AMI's root device name instead of `/dev/sda1`.
- All configuration, including TLS, is written before Nomad starts. ACL bootstrap is retried until it succeeds or reports that ACLs are already bootstrapped, with a deadline. It no longer uses IMDSv1 or writes the token to `/tmp`.
- TLS files are referenced by absolute paths.
- `chroot_env` covers RHEL layouts (`/etc/pki`, `/etc/crypto-policies`, `/etc/alternatives`) and drops `/lib32` and `/etc/timezone`.
- The raft backup script lives in `/etc/nomad.d` instead of `/usr/local/bin`, reads the token at run time, and no longer runs a backup as soon as the timer is enabled.
- The exec task DNS search domain is correct in `us-east-1`.

### Upgrading from v1

1. Store the existing gossip key and ACL bootstrap token as SecureString parameters, and the TLS files if TLS is enabled. See [Secrets](./README.md#secrets). Use the current values: servers keep their gossip keyring in the data directory, and an already bootstrapped cluster keeps its token.
2. Replace the removed inputs with `secrets_ssm_prefix` and the renamed inputs.
3. Replace the instances, for example with an ASG instance refresh, so they boot with the new launch template.

---

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
