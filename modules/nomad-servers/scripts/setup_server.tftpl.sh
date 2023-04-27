#!/usr/bin/env bash

#
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

# Send the log output from this script to user-data.log, syslog, and the console.
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

readonly SCRIPT_DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

function log {
  local readonly level="$1"
  local readonly message="$2"
  local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "$${timestamp} [$${level}] [$${SCRIPT_NAME}] $${message}"
}

function log_info {
  local readonly message="$1"
  log "INFO" "$${message}"
}

function log_warn {
  local readonly message="$1"
  log "WARN" "$${message}"
}

function log_error {
  local readonly message="$1"
  log "ERROR" "$${message}"
}

store_tags () {
  max_attempts=3
  count=0

  while true
  do
    TOKEN=$(curl -s --connect-timeout 1 --retry 3 --retry-delay 3  \
     -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    TAGS=$(curl -s --connect-timeout 1 --retry 3 --retry-delay 3  \
     -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance)

    # If there's no 'nomad-cluster' found in tags, retry.
    if [[ $${TAGS} != *"nomad-cluster"* ]];then
      sleep 1

      count=$((count+1))

      # If max retries still didn't get the data, fail.
      if [[ $count == $max_attempts ]]; then
          log_error "aborting as max attempts reached"
          exit 1;
      fi
      continue
    fi

    readarray -t ARR <<<"$TAGS"
    break

  done
}

set_hostname() {
for t in "$${ARR[@]}"
do
# For servers we'll use the `Name` tag of the EC2 instance.
if [ "$t" == "Name" ]; then
    TAG=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/tags/instance/$t")

    # The original hostname is like `ip-10-x-y-z`
    orig_hostname=$(sudo hostnamectl --static)
    # Replace `ip` with tag value.
    new_hostname=$(sed "s/ip/$${TAG}/g" <<<"$${orig_hostname}")
    log_info "setting hostname as $${new_hostname}"
    sudo hostnamectl set-hostname "$${new_hostname}"
    # Set as variable.
    HOSTNAME=$${new_hostname}
fi
done
}

get_launch_index(){
    AMI_LAUNCH_INDEX=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/ami-launch-index")
}

get_instance_id(){
    INSTANCE_ID=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/instance-id")
}

get_local_ipv4() {
  PRIVATE_IP=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/local-ipv4")
}

start_nomad() {
  sudo systemctl enable --now nomad
}

restart_nomad() {
  sudo systemctl restart nomad
}

prepare_nomad_server_config() {
  cat <<EOF > /etc/nomad.d/nomad.hcl
${nomad_server_cfg}
EOF
}

# Wait for the Nomad leader to be elected.
function wait_for_leader() {
  log_info "Waiting for leader node to be elected"
  max_retries=10
  retry=0
  while [ $retry -lt $max_retries ]; do
    if nomad operator api /v1/status/leader >/dev/null; then
      log_info "Leader node elected"
      return 0
    fi
    log_warn "Leader not yet elected. Retrying in 5 seconds..."
    sleep 5
    retry=$((retry + 1))
  done
  log_warn "Leader not elected after $max_retries attempts."
  return 1
}

bootstrap_init() {
  # Get the IP address of this node.
  local ip_address
  ip_address=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

  # Get the IP address of the Nomad leader.
  local nomad_leader_ip
  nomad_leader_ip=$(nomad operator api /v1/status/leader | tr -d '"' | cut -d':' -f1)

  log_info "Checking if this node is the Nomad leader"
  if [ "$ip_address" = "$nomad_leader_ip" ]; then
    log_info "This node is the Nomad leader. Proceeding with bootstrap process."
    echo "${nomad_acl_bootstrap_token}" > /tmp/bootstrap.token
    if nomad acl bootstrap - < /tmp/bootstrap.token >/dev/null 2>&1; then
      log_info "Nomad ACL bootstrap succeeded."
      rm /tmp/bootstrap.token
    else
      log_error "Nomad ACL bootstrap failed."
    fi
  else
    log_warn "This node is not the Nomad leader. Skipping bootstrap."
  fi
}

log_info "Fetching EC2 Tags from AWS"
store_tags

log_info "Fetching AMI Launch Index"
get_launch_index

log_info "Fetching Instance ID"
get_instance_id

log_info "Setting hostname of machine"
set_hostname

log_info "Fetching private IPv4 of machine"
get_local_ipv4

log_info "Rendering server config for nomad"
prepare_nomad_server_config

log_info "Starting Nomad service"
start_nomad

log_info "Waiting for Nomad to be ready"
wait_for_leader

log_info "Bootstrapping Nomad"
bootstrap_init

log_info "Restarting services"
restart_nomad

log_info "Finished server initializing process! Enjoy Nomad!"
