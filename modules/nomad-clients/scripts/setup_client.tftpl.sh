#!/usr/bin/env bash
# Script to bootstrap Nomad as client node.

# This script performs the following tasks:
# - Prepares DNS configuration for exec tasks
# - Renders the Nomad client configuration
# - Optionally, adds Docker configuration to Nomad if the 'enable_docker_plugin' variable is set to true
# - Starts the Nomad service

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
# For servers we'll use the NAME tag of the EC2 instance.
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

get_local_ipv4() {
  PRIVATE_IP=$(curl -s --retry 3 --retry-delay 3 --connect-timeout 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/local-ipv4")
}

prepare_dns_config() {
  echo "preparing dns config for exec"
  sudo mkdir -p /etc/nomad_exec/
  cat <<EOF > /etc/nomad_exec/resolv_r53.conf
nameserver ${route_53_resolver_address}
search ap-south-1.compute.internal
EOF
}

start_nomad() {
  sudo systemctl enable --now nomad
}

restart_nomad() {
  sudo systemctl restart nomad
}

prepare_nomad_client_config() {
  cat <<EOF > /etc/nomad.d/nomad.hcl
${nomad_client_cfg}
EOF

cat <<EOF >> /etc/nomad.d/nomad.hcl
vault {
  enabled          = false
}

client {
  enabled = true
  server_join {
    retry_join = ["provider=aws region=ap-south-1 tag_key=${nomad_join_tag_key} tag_value=${nomad_join_tag_value}"]
  }
  meta {
$(for t in "$${ARR[@]}"
do
  key=$(echo "$t" | sed -e "s|:|_|g")
  TAG=`curl -s --connect-timeout 3 --retry 3 --retry-delay 3  \
       -H "Accept: application/json" -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/tags/instance/$t"`
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
    "/etc/nomad_exec/resolv_r53.conf" = "/etc/resolv.conf"

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
  cat <<EOF >> /etc/nomad.d/nomad.hcl
plugin "docker" {
  config {
    auth {
      config = "/etc/docker/config.json"
      helper = "ecr-login"
    }
    allow_privileged = true
    volumes {
      enabled = true
    }
    extra_labels = ["job_name", "job_id", "task_group_name", "task_name", "namespace", "node_name", "node_id"]

    logging {
      type = "journald"
      config {
        tag    = "hashicluster_nomad"
        labels = "com.hashicorp.nomad.alloc_id,com.hashicorp.nomad.job_id,com.hashicorp.nomad.job_name,com.hashicorp.nomad.namespace,com.hashicorp.nomad.node_id,com.hashicorp.nomad.node_name,com.hashicorp.nomad.task_group_name,com.hashicorp.nomad.task_name"
      }
    }
  }
}
EOF
}


log_info "Fetching EC2 Tags from AWS"
store_tags

log_info "Setting hostname of machine"
set_hostname

log_info "Fetching private IPv4 of machine"
get_local_ipv4

log_info "Prepare DNS config for exec tasks"
prepare_dns_config

log_info "Rendering client config for nomad"
prepare_nomad_client_config

if [ ${enable_docker_plugin} == "true" ]; then
    log_info "Adding docker config to Nomad"
    add_docker_to_nomad
fi

log_info "Starting Nomad service"
start_nomad

log_info "Finished client initializing process! Enjoy Nomad!"
