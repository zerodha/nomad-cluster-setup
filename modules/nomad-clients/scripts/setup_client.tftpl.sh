#!/usr/bin/env bash

# Script to bootstrap Nomad as client node.

# This script performs the following tasks:
# - Prepares DNS configuration for exec tasks
# - Renders the Nomad client configuration
# - Optionally, adds Docker configuration to Nomad if the 'enable_docker_plugin' variable is set to true
# - Starts the Nomad service

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

# Ensures the resolv.conf within nomad `exec` jobs
# can access other machines
# see: https://github.com/hashicorp/nomad/issues/11033
prepare_dns_config() {
  cat <<EOF >/etc/nomad.d/route53_resolv.conf
nameserver ${route_53_resolver_address}
search ap-south-1.compute.internal
EOF
}

# Increase the file limit
modify_nomad_systemd_config() {
  if [ ${nomad_file_limit} > 65536 ]; then
    sudo sed -i '/^LimitNOFILE/s/=.*$/=${nomad_file_limit}/' /lib/systemd/system/nomad.service
  fi
}

# Function to check and load the bridge module
load_bridge() {
  if ! lsmod | grep -q "^bridge"; then
    log "INFO" "Bridge module not loaded. Attempting to load..."
    if ! modprobe bridge; then
      log "ERROR" "Failed to load bridge module. This might affect network functionality."
    else
      log "INFO" "Bridge module loaded successfully."
    fi
  else
    log "INFO" "Bridge module is already loaded."
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
prepare_nomad_client_config() {
  cat <<EOF >/etc/nomad.d/nomad.hcl
${nomad_client_cfg}
EOF

  cat <<EOF >>/etc/nomad.d/nomad.hcl
client {
  enabled = true
  server_join {
    retry_join = ["provider=aws region=ap-south-1 tag_key=${nomad_join_tag_key} tag_value=${nomad_join_tag_value}"]
  }
  meta {
$(for tag in "$${AWS_TAGS[@]}"; do
    key=$${tag//:/_}
    TAG=$(curl -s --connect-timeout 3 --retry 3 --retry-delay 3 \
      -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/tags/instance/$tag")
    echo -e "\tec2_$key = \"$TAG\""
  done)
  }
  chroot_env {
    # Defaults
    "/bin/"           = "/bin/"
    "/lib"            = "/lib"
    "/lib32"          = "/lib32"
    "/lib64"          = "/lib64"
    "/sbin"           = "/sbin"
    "/usr"            = "/usr"

    "/etc/ld.so.cache"  = "/etc/ld.so.cache"
    "/etc/ld.so.conf"   = "/etc/ld.so.conf"
    "/etc/ld.so.conf.d" = "/etc/ld.so.conf.d"
    "/etc/localtime"    = "/etc/localtime"
    "/etc/passwd"       = "/etc/passwd"
    "/etc/ssl"          = "/etc/ssl"
    "/etc/timezone"     = "/etc/timezone"

    # DNS
    "/etc/nomad.d/route53_resolv.conf" = "/etc/resolv.conf"

  }
}

plugin "exec" {
  config {
    allow_caps = ["audit_write", "chown", "dac_override", "fowner", "fsetid", "kill", "mknod",
    "net_bind_service", "setfcap", "setgid", "setpcap", "setuid", "sys_chroot", "sys_time"]
  }
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}
EOF
}

add_docker_to_nomad() {
  cat <<EOF >>/etc/nomad.d/nomad.hcl
plugin "docker" {
  config {
    auth {
      config = "/etc/docker/config.json"
    }
    allow_privileged = true
    volumes {
      enabled = true
    }
    extra_labels = ["job_name", "job_id", "task_group_name", "task_name", "namespace", "node_name", "node_id"]

    logging {
      type = "json-file"
      config {
        max-size = "10m"
        max-file = 10
      }
    }
  }
}
EOF
}



add_host_volumes_to_nomad() {
  cat <<EOF >>/etc/nomad.d/nomad.hcl
client {
  %{ for name, volume in nomad_client_exec_host_volumes }
  host_volume "${name}" {
    path      = "${volume.path}"
    read_only = ${volume.read_only}
  }
  %{ endfor }
}
EOF

  # Create directories if they don't exist
  %{ for name, volume in nomad_client_exec_host_volumes }
  if [ ! -d "${volume.path}" ]; then
    mkdir -p "${volume.path}"
  fi
  %{ endfor }
}

log "INFO" "Fetching EC2 Tags from AWS"
store_tags

log "INFO" "Setting machine hostname"
set_hostname

log "INFO" "Prepare DNS config for exec tasks"
prepare_dns_config

log "INFO" "Checking and loading bridge module"
load_bridge

log "INFO" "Rendering client config for nomad"
prepare_nomad_client_config

%{ if enable_docker_plugin }
log "INFO" "Adding docker config to Nomad"
add_docker_to_nomad
%{ endif }

%{ if length(nomad_client_exec_host_volumes) > 0 }
log "INFO" "Adding host volumes config to Nomad"
add_host_volumes_to_nomad
%{ else }
log "INFO" "No host volumes configured for Nomad client"
%{ endif }


log "INFO" "Modify Nomad systemd config"
modify_nomad_systemd_config

log "INFO" "Starting Nomad service"
start_nomad

log "INFO" "Finished client initializing process! Enjoy Nomad!"
