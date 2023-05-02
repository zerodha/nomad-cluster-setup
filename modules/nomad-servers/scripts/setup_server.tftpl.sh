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

# Enables nomad systemd service
start_nomad() {
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

bootstrap_init() {
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

log "INFO" "Fetching EC2 Tags from AWS"
store_tags

log "INFO" "Setting hostname of machine"
set_hostname

log "INFO" "Rendering server config for nomad"
prepare_nomad_server_config

log "INFO" "Starting Nomad service"
start_nomad

log "INFO" "Waiting for Nomad to be ready"
wait_for_leader

log "INFO" "Bootstrapping Nomad"
bootstrap_init

log "INFO" "Restarting services"
restart_nomad

log "INFO" "Finished server initializing process! Enjoy Nomad!"
