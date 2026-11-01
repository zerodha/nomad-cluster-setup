#!/usr/bin/env bash

# Configures and starts a Nomad server, then bootstraps ACLs.
#
# All configuration is written before Nomad starts. Secrets are read from SSM
# Parameter Store at boot so they never appear in user data. The script is
# safe to rerun: it rewrites every file and restarts Nomad.

set -Eeuo pipefail

readonly AWS_REGION="${aws_region}"
readonly SECRETS_SSM_PREFIX="${secrets_ssm_prefix}"
readonly SECRET_TIMEOUT=300

log() {
  printf '%s [%s] setup_server: %s\n' "$(date -u +%FT%TZ)" "$1" "$2" >&2
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

%{ if acl_enabled ~}
readonly ACL_BOOTSTRAP_TIMEOUT=600

# Every server tries to bootstrap. The first request to reach the leader wins
# and the rest get "already done", so no leader check is needed.
bootstrap_acl() {
  local deadline=$((SECONDS + ACL_BOOTSTRAP_TIMEOUT)) out
  until out=$(nomad acl bootstrap /etc/nomad.d/acl_bootstrap_token 2>&1 >/dev/null); do
    if [[ $out == *"ACL bootstrap already done"* ]]; then
      log INFO "ACLs are already bootstrapped"
      return 0
    fi
    if ((SECONDS >= deadline)); then
      log ERROR "timed out bootstrapping ACLs: $out"
      return 1
    fi
    sleep 10
  done
  log INFO "bootstrapped ACLs"
}
%{ endif ~}

log INFO "writing Nomad configuration"
install -d -m 0755 /etc/nomad.d /etc/systemd/system/nomad.service.d
rm -f /etc/nomad.d/nomad.hcl

write_file /etc/nomad.d/base.hcl 0644 <<'NOMAD_CONFIG'
${chomp(base_hcl)}
NOMAD_CONFIG

write_file /etc/nomad.d/server.hcl 0644 <<'NOMAD_CONFIG'
${chomp(server_hcl)}
NOMAD_CONFIG
%{ if extra_config != "" ~}

# Loaded last, so it overrides the files above.
write_file /etc/nomad.d/zz-extra.hcl 0644 <<'NOMAD_CONFIG'
${chomp(extra_config)}
NOMAD_CONFIG
%{ endif ~}

write_file /etc/nomad.d/cli.env 0644 <<'NOMAD_CONFIG'
%{ if tls_enabled && tls_http_enable ~}
NOMAD_ADDR=https://127.0.0.1:4646
NOMAD_CACERT=/etc/nomad.d/tls/ca.pem
NOMAD_CLIENT_CERT=/etc/nomad.d/tls/cert.pem
NOMAD_CLIENT_KEY=/etc/nomad.d/tls/key.pem
NOMAD_TLS_SERVER_NAME=server.${nomad_region}.nomad
%{ else ~}
NOMAD_ADDR=http://127.0.0.1:4646
%{ endif ~}
NOMAD_CONFIG

write_file /etc/systemd/system/nomad.service.d/nomad-cluster-setup.conf 0644 <<'NOMAD_CONFIG'
[Service]
LimitNOFILE=${nomad_file_limit}
NOMAD_CONFIG

log INFO "reading secrets from $SECRETS_SSM_PREFIX"
gossip_key=$(ssm_get gossip_key)
write_file /etc/nomad.d/secrets.hcl 0600 <<EOF
server {
  encrypt = "$gossip_key"
}
EOF
%{ if acl_enabled ~}
fetch_secret acl_bootstrap_token /etc/nomad.d/acl_bootstrap_token
%{ endif ~}
%{ if tls_enabled ~}
install -d -m 0700 /etc/nomad.d/tls
fetch_secret tls/ca_cert /etc/nomad.d/tls/ca.pem
fetch_secret tls/cert /etc/nomad.d/tls/cert.pem
fetch_secret tls/key /etc/nomad.d/tls/key.pem

write_file /etc/nomad.d/tls.hcl 0644 <<'NOMAD_CONFIG'
${chomp(tls_hcl)}
NOMAD_CONFIG
%{ endif ~}
%{ if raft_backup_bucket != "" ~}

log INFO "installing the raft snapshot backup timer"
write_file /etc/nomad.d/backup.sh 0755 <<'NOMAD_CONFIG'
#!/usr/bin/env bash
# Saves a raft snapshot to S3 when this server is the leader.
set -euo pipefail
%{ if acl_enabled ~}
NOMAD_TOKEN=$(</etc/nomad.d/acl_bootstrap_token)
export NOMAD_TOKEN
%{ endif ~}
if ! nomad agent-info | grep -q 'leader = true'; then
  exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
file="nomad-snapshot-$(date -u +%Y%m%d-%H%M%S).snap"
nomad operator snapshot save "$dir/$file"
gzip "$dir/$file"
aws s3 cp --region "${aws_region}" "$dir/$file.gz" "s3://${raft_backup_bucket}/${cluster_name}/$file.gz"
NOMAD_CONFIG

write_file /etc/systemd/system/nomad-backup.service 0644 <<'NOMAD_CONFIG'
[Unit]
Description=Nomad raft snapshot backup
After=nomad.service

[Service]
Type=oneshot
EnvironmentFile=/etc/nomad.d/cli.env
ExecStart=/bin/bash /etc/nomad.d/backup.sh
NOMAD_CONFIG

write_file /etc/systemd/system/nomad-backup.timer 0644 <<'NOMAD_CONFIG'
[Unit]
Description=Run the Nomad raft snapshot backup twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
Persistent=true

[Install]
WantedBy=timers.target
NOMAD_CONFIG
%{ endif ~}

log INFO "starting Nomad"
systemctl daemon-reload
systemctl enable nomad
systemctl restart nomad
%{ if raft_backup_bucket != "" ~}
systemctl enable --now nomad-backup.timer
%{ endif ~}
%{ if acl_enabled ~}

log INFO "bootstrapping ACLs"
set -a
# shellcheck source=/dev/null
. /etc/nomad.d/cli.env
set +a
bootstrap_acl
%{ endif ~}

log INFO "done"
