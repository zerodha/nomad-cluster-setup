#!/usr/bin/env bash

# Script to configure and bootstrap Nomad server nodes in an AWS Auto Scaling group.
#
# This script performs the following steps:
# - Configures the Nomad agent as a server on the EC2 instances.
# - Bootstraps the Nomad ACL system with a pre-configured token on the first server.
# - Joins the Nomad server nodes to form a cluster.
# - Starts the Nomad agent service.
#
# This script should be run on each Nomad server node as part of the EC2 instance launch process.
#

set -Eeuo pipefail

declare -r SCRIPT_NAME="$(basename "$0")"

declare -ag AWS_TAGS=()

# Send the log output from this script to user-data.log, syslog, and the console.
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Wrapper to log any outputs from the script to stderr
function log {
  declare -r LVL="$1"
  declare -r MSG="$2"
  declare -r TS=$(date +"%Y-%m-%d %H:%M:%S")
  echo >&2 -e "$TS [$LVL] [$SCRIPT_NAME] $MSG"
}

# Stores AWS tags to use as nomad client meta
# Requires `nomad-cluster` tag to be defined
# within AWS instance tags
store_tags() {
  max_attempts=3
  count=0

  while true; do
    TOKEN=$(curl -s --connect-timeout 1 --retry 3 --retry-delay 3 \
      -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    TAGS=$(curl -s --connect-timeout 1 --retry 3 --retry-delay 3 \
      -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance)

    # If there's no 'nomad-cluster' found in tags, retry.
    if [[ "$${TAGS}" != *"nomad-cluster"* ]]; then
      sleep 1

      count=$((count + 1))

      # If max retries still didn't get the data, fail.
      if [[ $count -eq $max_attempts ]]; then
        log "ERROR" "aborting as max attempts reached"
        exit 1
      fi
      continue
    fi

    readarray -t AWS_TAGS <<<"$TAGS"
    break

  done
}

# Sets hostname for the system
# Replaces `ip` in the hostname with the AWS instance `Name` tag
set_hostname() {
  for t in "$${AWS_TAGS[@]}"; do
    # For servers we'll use the NAME tag of the EC2 instance.
    if [ "$t" == "Name" ]; then
      TAG=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3 \
        -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/tags/instance/$t")

      # The original hostname is like `ip-10-x-y-z`
      CURR_HOSTNAME=$(sudo hostnamectl --static)
      # Replace `ip` with tag value.
      HOSTNAME="$${CURR_HOSTNAME//ip/$TAG}"
      log "INFO" "setting hostname as $HOSTNAME"
      sudo hostnamectl set-hostname "$HOSTNAME"
    fi
  done
}

# Increase the file limit
modify_nomad_systemd_config() {
  if [ "${nomad_file_limit}" -gt "65536" ]; then
    sudo sed -i '/^LimitNOFILE/s/=.*$/=${nomad_file_limit}/' /lib/systemd/system/nomad.service
  fi
}

# Enables nomad systemd service
start_nomad() {
  sudo systemctl daemon-reload
  sudo systemctl enable --now nomad
}

# Restarts nomad systemd service
restart_nomad() {
  sudo systemctl restart nomad
}

# Sets up `/etc/nomad.d`
prepare_nomad_server_config() {
  cat <<EOF >/etc/nomad.d/nomad.hcl
${nomad_server_cfg}
EOF
}

# Wait for the Nomad leader to be elected.
wait_for_leader() {
  log "INFO" "Waiting for leader node to be elected"
  max_retries=10
  retry=0
  while [ $retry -lt $max_retries ]; do
    if nomad operator api /v1/status/leader >/dev/null; then
      log "INFO" "Leader node elected"
      return 0
    fi
    log "WARN" "Leader not yet elected. Retrying in 5 seconds..."
    sleep 5
    retry=$((retry + 1))
  done
  log "WARN" "Leader not elected after $max_retries attempts."
  return 1
}

bootstrap_acl() {
  # Get the IP address of this node.
  local ip_address
  ip_address=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

  # Get the IP address of the Nomad leader.
  local nomad_leader_ip
  nomad_leader_ip=$(nomad operator api /v1/status/leader | tr -d '"' | cut -d':' -f1)

  log "INFO" "Checking if this node is the Nomad leader"
  if [ "$ip_address" = "$nomad_leader_ip" ]; then
    log "INFO" "This node is the Nomad leader. Proceeding with bootstrap process."
    echo "${nomad_acl_bootstrap_token}" >/tmp/bootstrap.token
    if nomad acl bootstrap - </tmp/bootstrap.token >/dev/null 2>&1; then
      log "INFO" "Nomad ACL bootstrap succeeded."
      rm /tmp/bootstrap.token
    else
      log "ERROR" "Nomad ACL bootstrap failed."
    fi
  else
    log "WARN" "This node is not the Nomad leader. Skipping bootstrap."
  fi
}

# Sets up the backup script and systemd timer for Nomad state backups
setup_state_backup() {
  log "INFO" "Setting up Nomad state backup to S3"

  # Create backup script
  cat <<EOF >/usr/local/bin/nomad-backup.sh
#!/usr/bin/env bash

set -e

BACKUP_FILE="nomad-snapshot-\$(date +%Y%m%d-%H%M%S).snap"
S3_BUCKET="${nomad_raft_backup_bucket}"
CLUSTER_NAME="${nomad_dc}"
LOG_FILE="/var/log/nomad-backup.log"
%{ if nomad_acl_enable }
NOMAD_TOKEN="${nomad_acl_bootstrap_token}"
%{ endif }

# Log to the file and console
log() {
  echo "\$(date +"%Y-%m-%d %H:%M:%S") [\$1] \$2" | tee -a \$LOG_FILE
}

# Check if this node is the leader
is_leader() {
  %{ if nomad_acl_enable }
  LEADER_CHECK=\$(NOMAD_TOKEN=\$NOMAD_TOKEN nomad agent-info | grep "leader = true" || echo "")
  %{ else }
  LEADER_CHECK=\$(nomad agent-info | grep "leader = true" || echo "")
  %{ endif }

  if [ -n "\$LEADER_CHECK" ]; then
    return 0
  else
    return 1
  fi
}

# Main backup function
perform_backup() {
  log "INFO" "Starting Nomad state backup"

  # Check if we're the leader
  if ! is_leader; then
    log "INFO" "This node is not the leader, skipping backup"
    exit 0
  fi

  log "INFO" "This node is the leader, performing backup"

  # Create temp directory
  TEMP_DIR=\$(mktemp -d)
  cd \$TEMP_DIR

  # Create snapshot
  log "INFO" "Creating Nomad snapshot"
  %{ if nomad_acl_enable }
  NOMAD_TOKEN=\$NOMAD_TOKEN nomad operator snapshot save \$BACKUP_FILE
  %{ else }
  nomad operator snapshot save \$BACKUP_FILE
  %{ endif }

  # Compress the snapshot
  log "INFO" "Compressing snapshot"
  gzip \$BACKUP_FILE

  # Upload to S3
  log "INFO" "Uploading snapshot to S3"
  aws s3 cp "\$BACKUP_FILE.gz" "s3://\$S3_BUCKET/\$CLUSTER_NAME/\$BACKUP_FILE.gz"

  # Clean up
  log "INFO" "Cleaning up temporary files"
  rm -rf \$TEMP_DIR

  log "INFO" "Backup completed successfully"
}

# Execute the backup
perform_backup
EOF

  # Make the script executable
  chmod +x /usr/local/bin/nomad-backup.sh

  # Create systemd timer unit
  cat <<EOF >/etc/systemd/system/nomad-backup.timer
[Unit]
Description=Run Nomad backup twice daily
Requires=nomad-backup.service

[Timer]
OnCalendar=*-*-* 00,12:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Create systemd service unit
  cat <<EOF >/etc/systemd/system/nomad-backup.service
[Unit]
Description=Nomad State Backup Service
After=nomad.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nomad-backup.sh
User=root

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start the timer
  systemctl daemon-reload
  systemctl enable nomad-backup.timer
  systemctl start nomad-backup.timer

  log "INFO" "Nomad state backup has been configured successfully"
}

log "INFO" "Fetching EC2 Tags from AWS"
store_tags

log "INFO" "Setting hostname of machine"
set_hostname

log "INFO" "Rendering server config for nomad"
prepare_nomad_server_config

log "INFO" "Modify Nomad systemd config"
modify_nomad_systemd_config

log "INFO" "Starting Nomad service"
start_nomad

log "INFO" "Waiting for Nomad to be ready"
wait_for_leader

%{ if nomad_acl_enable }
log "INFO" "Bootstrapping ACL for Nomad"
bootstrap_acl
%{else}
log "INFO" "Skipping ACL Bootstrap for Nomad as 'nomad_acl_enable' is not set to true"
%{ endif }

%{ if nomad_raft_backup_bucket != "" }
log "INFO" "Setting up state backup to S3"
setup_state_backup
%{else}
log "INFO" "Skipping state backup setup as 'nomad_raft_backup_bucket' is not defined"
%{ endif }

log "INFO" "Restarting services"
restart_nomad

log "INFO" "Finished server initializing process! Enjoy Nomad!"
