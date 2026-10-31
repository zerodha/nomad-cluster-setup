#!/usr/bin/env bash

# Configures and starts a Nomad client.
#
# All configuration is written before Nomad starts. TLS material is read from
# SSM Parameter Store at boot so it never appears in user data. The script is
# safe to rerun: it rewrites every file and restarts Nomad.

set -Eeuo pipefail

log() {
  printf '%s [%s] setup_client: %s\n' "$(date -u +%FT%TZ)" "$1" "$2" >&2
}

trap 'log ERROR "failed at line $LINENO"' ERR

# Atomically writes stdin to a file with the given mode.
write_file() {
  local path="$1" mode="$2" tmp
  tmp=$(mktemp "$path.XXXXXX")
  cat >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

%{ if tls_enabled ~}
readonly AWS_REGION="${aws_region}"
readonly SECRETS_SSM_PREFIX="${secrets_ssm_prefix}"
readonly SECRET_TIMEOUT=300

# Prints a SecureString parameter. All errors are retried until SECRET_TIMEOUT
# because new instance roles and parameters can take a while to propagate.
ssm_get() {
  local name="$SECRETS_SSM_PREFIX/$1" deadline=$((SECONDS + SECRET_TIMEOUT))
  until aws ssm get-parameter --region "$AWS_REGION" --name "$name" \
    --with-decryption --query Parameter.Value --output text; do
    if ((SECONDS >= deadline)); then
      log ERROR "timed out reading $name"
      return 1
    fi
    log WARN "retrying read of $name"
    sleep 5
  done
}

# Copies a SecureString parameter into a root-only file.
fetch_secret() {
  local value
  value=$(ssm_get "$1")
  write_file "$2" 0600 <<<"$value"
}
%{ endif ~}

log INFO "writing Nomad configuration"
install -d -m 0755 /etc/nomad.d /etc/systemd/system/nomad.service.d
rm -f /etc/nomad.d/nomad.hcl

write_file /etc/nomad.d/base.hcl 0644 <<'NOMAD_CONFIG'
${chomp(base_hcl)}
NOMAD_CONFIG

write_file /etc/nomad.d/client.hcl 0644 <<'NOMAD_CONFIG'
${chomp(client_hcl)}
NOMAD_CONFIG

# Exec tasks use this file as /etc/resolv.conf through chroot_env.
# See https://github.com/hashicorp/nomad/issues/11033
write_file /etc/nomad.d/route53_resolv.conf 0644 <<'NOMAD_CONFIG'
nameserver ${route_53_resolver_address}
search ${dns_search_domain}
NOMAD_CONFIG

write_file /etc/systemd/system/nomad.service.d/nomad-cluster-setup.conf 0644 <<'NOMAD_CONFIG'
%{ if docker_enabled ~}
# Stop Nomad before Docker so the shutdown drain can still stop containers
# gracefully.
[Unit]
After=docker.service

%{ endif ~}
[Service]
LimitNOFILE=${nomad_file_limit}
# Leave room for drain_on_shutdown to finish before systemd kills Nomad.
TimeoutStopSec=${drain_deadline} 30s
NOMAD_CONFIG
%{ for volume in host_volumes ~}
install -d "${volume.path}"
%{ endfor ~}
%{ if tls_enabled ~}

log INFO "reading TLS material from $SECRETS_SSM_PREFIX"
install -d -m 0700 /etc/nomad.d/tls
fetch_secret tls/ca_cert /etc/nomad.d/tls/ca.pem
fetch_secret tls/cert /etc/nomad.d/tls/cert.pem
fetch_secret tls/key /etc/nomad.d/tls/key.pem

write_file /etc/nomad.d/tls.hcl 0644 <<'NOMAD_CONFIG'
${chomp(tls_hcl)}
NOMAD_CONFIG
%{ endif ~}

log INFO "starting Nomad"
systemctl daemon-reload
systemctl enable nomad
systemctl restart nomad

log INFO "done"
