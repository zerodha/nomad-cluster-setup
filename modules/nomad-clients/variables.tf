# Common Configuration

variable "ami" {
  description = "Amazon Machine Image (AMI) ID used for deploying Nomad clients"
  type        = string
  nullable    = false
}

variable "client_name" {
  description = "Name of the Auto Scaling Group (ASG) nodes deployed as Nomad clients"
  type        = string
  nullable    = false
}

variable "client_security_groups" {
  description = "List of security groups to attach to the Nomad client nodes"
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "Identifier used for naming all resources associated with the cluster. 1-28 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  type        = string
  nullable    = false

  # Same rule as nomad-servers, which names its ALB "<cluster_name>-web" and
  # AWS caps ALB names at 32 characters.
  validation {
    condition     = length(var.cluster_name) <= 28 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster_name value must be 1-28 lowercase letters, digits or hyphens, and must start and end with a letter or digit."
  }
}

variable "iam_policy_arns" {
  description = "Extra IAM policy ARNs to attach to the Nomad client role. Ignored when `iam_instance_profile` is set."
  type        = list(string)
  default     = []
}

variable "ebs_volume_size" {
  description = "The size of the EBS volume in gigabytes"
  type        = number
  default     = 100
}

variable "ebs_encryption" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

variable "ebs_tags" {
  description = "A map of custom tags to be assigned to the EBS volumes"
  type        = map(string)
  default     = {}
}

variable "ec2_tags" {
  description = "A map of custom tags to be assigned to the EC2 instances"
  type        = map(string)
  default     = {}
}

variable "ebs_volume_type" {
  description = "The type of EBS volume (gp2, gp3, io1, io2, sc1, st1)"
  type        = string
  default     = "gp3"
}

variable "ebs_iops" {
  description = "The amount of provisioned IOPS for the EBS volume (only valid for gp3, io1, io2)"
  type        = number
  default     = 3000
}

variable "enable_docker_plugin" {
  description = "Whether to enable the Docker plugin on the client nodes"
  type        = bool
  default     = true
}

variable "docker_allow_privileged" {
  description = "Allow Docker tasks to set `privileged = true`. A privileged container has root on the host."
  type        = bool
  default     = false
}

variable "enable_raw_exec" {
  description = "Enable the raw_exec driver. Its tasks run as root on the host with no isolation, so any job that can be submitted can take over the node."
  type        = bool
  default     = false
}

variable "tls_enabled" {
  description = "Enable TLS. The CA, certificate and key are read at boot from the `tls/ca_cert`, `tls/cert` and `tls/key` parameters under `secrets_ssm_prefix`. The certificate must be valid for `client.<nomad_region>.nomad`."
  type        = bool
  default     = false
}

variable "tls_http_enable" {
  description = "Enable TLS and client certificate verification on the HTTP API when `tls_enabled` is true"
  type        = bool
  default     = false
}

variable "tls_rpc_enable" {
  description = "Enable TLS on RPC traffic when `tls_enabled` is true"
  type        = bool
  default     = true
}

variable "iam_instance_profile" {
  description = "Name of an existing IAM instance profile to use instead of creating one. Its role needs the SSM, KMS and EC2 permissions that the module would otherwise grant."
  type        = string
  default     = ""
}

variable "iam_tags" {
  description = "A map of custom tags to be assigned to the IAM role"
  type        = map(string)
  default     = {}
}

variable "instance_type" {
  description = "Instance type to use for the Nomad clients"
  type        = string
  default     = "c5a.large"
}

variable "route_53_resolver_address" {
  description = "Route53 resolver address for querying DNS inside exec tasks"
  type        = string
  nullable    = false
}

variable "nomad_join_tag_value" {
  description = "The value of the tag used for Nomad server auto-join"
  type        = string
  nullable    = false
}

variable "subnets" {
  description = "List of subnets to assign for deploying instances"
  type        = list(string)
  default     = []
}

# Autoscale Group Configuration

variable "autoscale_metrics" {
  description = "List of autoscaling metrics to monitor for Auto Scaling Group (ASG) instances"
  type        = list(string)
  default = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
}

variable "cluster_tags" {
  description = "Key-value pairs of tags to assign to the EC2 instances spawned by the ASG"
  type        = map(string)
}

variable "healthcheck_type" {
  description = "Health check type for the ASG, either 'EC2' or 'ELB'"
  type        = string
  default     = "EC2"
  validation {
    condition     = var.healthcheck_type == "EC2" || var.healthcheck_type == "ELB"
    error_message = "The healthcheck_type variable must be either 'EC2' or 'ELB'"
  }
}

variable "health_check_grace_period" {
  description = "The time (in seconds) to allow instances in the Auto Scaling group to warm up before beginning health checks."
  type        = number
  default     = 180
}

variable "instance_desired_count" {
  description = "Desired number of Nomad clients to run"
  type        = number
  default     = 1
}

variable "instance_max_count" {
  description = "Maximum number of Nomad clients to run"
  type        = number
  default     = 3
}

variable "instance_min_count" {
  description = "Minimum number of Nomad clients to run"
  type        = number
  default     = 0
}

variable "override_instance_types" {
  description = "List of instance types to define in the mixed_instances_policy block"
  type        = list(string)
  default     = []
  nullable    = true
}

variable "target_group_arns" {
  description = "List of target groups assigned in the ALB to connect to the ASG"
  type        = list(string)
  default     = []
}

variable "wait_for_capacity_timeout" {
  description = "Time for which Terraform waits after ASG creation to see if instances are running."
  type        = string
  default     = "10m"
}

variable "nomad_acl_enable" {
  description = "Whether to enable ACLs on the Nomad cluster or not"
  type        = bool
  default     = true
}

variable "nomad_file_limit" {
  description = "Value for LimitNOFILE in nomad systemd config"
  type        = number
  default     = 900000
}

variable "nomad_client_exec_host_volumes" {
  description = "A map of host volumes to configure for the Nomad client. Each path is created at boot, so on images with a read-only root it must be under a writable location such as /var or /opt/nomad."
  type = map(object({
    path      = string
    read_only = bool
  }))
  default = {}

  validation {
    condition     = alltrue([for volume in values(var.nomad_client_exec_host_volumes) : can(regex("^/[A-Za-z0-9_./-]*$", volume.path))])
    error_message = "Host volume paths must be absolute and may only contain letters, digits, \"_\", \".\", \"-\" and \"/\"."
  }
}

variable "extra_script" {
  description = "Path to custom script to be run as part of cloud-init"
  type        = string
  default     = ""
}

variable "extra_script_content" {
  description = "Inline cloud-init shell script content. Takes precedence over extra_script if set."
  type        = string
  default     = ""
}

variable "http_put_response_hop_limit" {
  description = "The hop limit for HTTP PUT response for the EC2 instance metadata service. The default of 1 keeps the instance credentials away from containers on bridge networks."
  type        = number
  default     = 1
}

variable "http_tokens" {
  description = "Whether the metadata service requires session tokens, also referred to as Instance Metadata Service Version 2 (IMDSv2). Can be 'optional', 'required', or 'no-preference'."
  type        = string
  default     = "required"
}

variable "nomad_gc_interval" {
  description = "Interval between garbage collections for Nomad client allocations"
  type        = string
  default     = "1m"
}

variable "nomad_gc_disk_usage_threshold" {
  description = "Disk usage percent threshold at which the GC will mark allocations as eligible for collection"
  type        = number
  default     = 80
}

variable "nomad_gc_inode_usage_threshold" {
  description = "Inode usage percent threshold at which the GC will mark allocations as eligible for collection"
  type        = number
  default     = 70
}

variable "nomad_gc_max_allocs" {
  description = "Terminal allocations a client keeps on disk before it deletes the oldest. Their task logs go with them, so raise this to keep logs of frequent cron runs."
  type        = number
  default     = 50
}

variable "nomad_gc_parallel_destroys" {
  description = "Number of parallel allocation destroys during garbage collection"
  type        = number
  default     = 2
}

variable "nomad_region" {
  description = "Nomad region name for the agents"
  type        = string
  default     = "global"
  nullable    = false
}

variable "nomad_datacenter" {
  description = "Nomad datacenter name for the agents. Defaults to `cluster_name`."
  type        = string
  default     = null
}

variable "node_pool" {
  description = "Nomad node pool for the clients"
  type        = string
  default     = "default"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,128}$", var.node_pool)) && var.node_pool != "all"
    error_message = "The node_pool value must be 1-128 letters, digits, \"_\" or \"-\", and must not be \"all\"."
  }
}

variable "drain_deadline" {
  description = "How long a client drains its allocations on shutdown before stopping them, as a duration such as `5m` or `1h30m`"
  type        = string
  default     = "5m"
  nullable    = false

  validation {
    condition     = can(regex("^([0-9]+(ms|s|m|h))+$", var.drain_deadline))
    error_message = "The drain_deadline value must be a duration made of ms, s, m or h units, such as \"5m\" or \"1h30m\"."
  }
}

variable "secrets_ssm_prefix" {
  description = "SSM Parameter Store path that holds the cluster secrets as SecureString parameters, for example `/nomad/example`. With `tls_enabled`, clients read `tls/ca_cert`, `tls/cert` and `tls/key` under it at boot."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(/[A-Za-z0-9_.-]+)+$", var.secrets_ssm_prefix))
    error_message = "The secrets_ssm_prefix value must start with \"/\", must not end with \"/\", and may only contain letters, digits, \"_\", \".\", \"-\" and \"/\"."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer managed KMS key that encrypts the secrets. Leave null when the parameters use the AWS managed `aws/ssm` key."
  type        = string
  default     = null
}

variable "nomad_extra_config" {
  description = "Extra Nomad agent configuration in HCL, written to /etc/nomad.d/zz-extra.hcl. It loads last, so it overrides module defaults. Takes effect on instances launched after the change."
  type        = string
  default     = ""
}

variable "static_nodes" {
  description = <<-EOT
    Stateful nodes, keyed by a short name such as `pg-1`. When set, the module
    creates one instance per key instead of the ASG. Each node gets its own EBS
    data volume in its subnet's AZ, mounted at `data_volume_mount_path` and
    exposed as the `data_volume_host_volume` Nomad host volume, plus node meta
    `static_node = <key>` for constraints. The volume outlives the instance.
  EOT
  type = map(object({
    subnet_id              = string
    data_volume_size       = number
    instance_type          = optional(string)
    data_volume_type       = optional(string, "gp3")
    data_volume_iops       = optional(number)
    data_volume_throughput = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.static_nodes) : can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", key))])
    error_message = "static_nodes keys must be 1-20 lowercase letters, digits or hyphens, and start and end with a letter or digit."
  }
}

variable "data_volume_mount_path" {
  description = "Where static nodes mount their data volume"
  type        = string
  default     = "/var/lib/nomad-data"
}

variable "data_volume_host_volume" {
  description = "Nomad host volume name for the data volume on static nodes"
  type        = string
  default     = "data"
}

variable "data_volume_tags" {
  description = "Extra tags for static node data volumes, such as AWS Backup selectors. Applied after ebs_tags."
  type        = map(string)
  default     = {}
}

variable "data_volume_kms_key_arn" {
  description = "KMS key for static node data volumes. Null uses the account's default EBS key."
  type        = string
  default     = null
}

variable "static_termination_protection" {
  description = "Enable EC2 termination protection on static nodes. Turn it off for the apply that replaces a node."
  type        = bool
  default     = true
}
