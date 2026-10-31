variable "alb_certificate_arn" {
  description = "ARN of the HTTPS certificate to use with the ALB"
  type        = string
  default     = ""
}

variable "ami" {
  description = "AMI ID to use for deploying Nomad servers"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^ami-", var.ami))
    error_message = "The AMI ID must start with 'ami-'."
  }
}


variable "autoscale_metrics" {
  description = "List of autoscaling metrics to enable for the Autoscaling Group"
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

variable "cluster_name" {
  description = "Identifier for the cluster, used as a prefix for all resources. 1-28 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  type        = string
  nullable    = false

  # The ALB is named "<cluster_name>-web" and AWS caps ALB names at 32 characters.
  validation {
    condition     = length(var.cluster_name) <= 28 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster_name value must be 1-28 lowercase letters, digits or hyphens, and must start and end with a letter or digit."
  }
}

variable "cluster_tags" {
  description = "Map of tag key-value pairs to assign to the EC2 instances spawned by the ASG"
  type        = map(string)
}

variable "create_alb" {
  description = "Whether to create an ALB for the Nomad servers or not"
  type        = bool
  default     = false
}

variable "iam_policy_arns" {
  description = "Extra IAM policy ARNs to attach to the Nomad server role, for example S3 access for raft backups"
  type        = list(string)
  default     = []
}

variable "default_security_groups" {
  description = "List of security group IDs to assign to the Nomad server instances"
  type        = list(string)
  default     = []
}

variable "ebs_tags" {
  description = "A map of additional tags to apply to the EBS volumes"
  type        = map(string)
  default     = {}
}

variable "ec2_tags" {
  description = "A map of additional tags to apply to the EC2 instances"
  type        = map(string)
  default     = {}
}

variable "ebs_encryption" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

variable "nomad_enable_mem_oversubscription" {
  description = "Whether to enable Memory Oversubscription on the cluster"
  type        = bool
  default     = false
}

variable "tls_enabled" {
  description = "Enable TLS. The CA, certificate and key are read at boot from the `tls/ca_cert`, `tls/cert` and `tls/key` parameters under `secrets_ssm_prefix`. The certificate must be valid for `server.<nomad_region>.nomad`."
  type        = bool
  default     = false
}

variable "tls_http_enable" {
  description = "Enable TLS and client certificate verification on the HTTP API when `tls_enabled` is true. CLI users then need the NOMAD_CACERT, NOMAD_CLIENT_CERT and NOMAD_CLIENT_KEY variables."
  type        = bool
  default     = false
}

variable "tls_rpc_enable" {
  description = "Enable TLS on RPC and Raft traffic when `tls_enabled` is true"
  type        = bool
  default     = true
}

variable "instance_count" {
  description = "Number of Nomad server instances to run. Also used as `bootstrap_expect`."
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count != 2
    error_message = "Set server size to 1 or > 2 for failure tolerance (3 to 5 recommended). See: https://developer.hashicorp.com/nomad/docs/concepts/consensus#deployment-table"
  }
}

variable "instance_type" {
  description = "Instance type to use for the Nomad server instances"
  type        = string
  default     = "c5a.large"
}

variable "iam_tags" {
  description = "A map of custom tags to be assigned to the IAM role"
  type        = map(string)
  default     = {}
}

variable "nomad_acl_enable" {
  description = "Whether to enable ACLs on the Nomad cluster or not"
  type        = bool
  default     = true
}

variable "nomad_alb_hostname" {
  description = "ALB hostname to use for accessing the Nomad web UI"
  type        = string
  default     = "nomad.example.internal"
}

variable "nomad_join_tag_value" {
  description = "Value of the tag used for Nomad server auto-join"
  type        = string
  nullable    = false
}

variable "nomad_raft_backup_bucket" {
  description = "The S3 bucket to use for backing up Nomad RAFT snapshot"
  type        = string
  default     = ""
}

variable "nomad_server_incoming_ips" {
  description = "List of IPs to allow incoming connections from to Nomad server ALBs"
  type        = list(string)
  default     = []
}

variable "nomad_server_incoming_security_groups" {
  description = "List of Security Groups to allow incoming connections from to Nomad server ALBs"
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = "List of subnets to assign for deploying instances"
  type        = list(string)
  default     = []
}

variable "vpc" {
  description = "ID of the AWS VPC to deploy all the resources in"
  type        = string
  nullable    = false
}

variable "nomad_file_limit" {
  description = "Value for LimitNOFILE in nomad systemd config"
  type        = number
  default     = 900000
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

variable "nomad_http_max_conns_per_client" {
  description = "Maximum number of concurrent connections per client IP for Nomad's HTTP API. Increase this when running behind a load balancer to avoid 'too many concurrent connections' errors."
  type        = number
  default     = 100
}

variable "nomad_job_gc_threshold" {
  description = "Minimum time a job must be in terminal state before it is eligible for garbage collection"
  type        = string
  default     = "4h"
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

variable "secrets_ssm_prefix" {
  description = "SSM Parameter Store path that holds the cluster secrets as SecureString parameters, for example `/nomad/example`. Servers read `gossip_key` and, with ACLs enabled, `acl_bootstrap_token` under it at boot."
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
