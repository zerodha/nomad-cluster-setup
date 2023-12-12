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

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the Nomad cluster in"
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Identifier for the cluster, used as a prefix for all resources"
  type        = string
  nullable    = false
  validation {
    condition     = endswith(var.cluster_name, "-nomad")
    error_message = "The cluster_name value must be suffixed with -nomad"
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

variable "default_iam_policies" {
  description = "List of IAM policy ARNs to attach to the Nomad server instances"
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

variable "ebs_encryption" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

variable "enable_mem_oversubscription" {
  description = "Whether to enable Memory Oversubscription on the cluster"
  type        = bool
  default     = false
}

variable "instance_count" {
  description = "Number of Nomad server instances to run"
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

# TODO: Add validation for the token format
# TODO: Add validation to check if acl is enabled then value can't be null.
variable "nomad_acl_bootstrap_token" {
  description = "Nomad ACL bootstrap token to use for bootstrapping ACLs"
  type        = string
  sensitive   = true
  default     = ""
  # nullable    = true
}

variable "nomad_alb_hostname" {
  description = "ALB hostname to use for accessing the Nomad web UI"
  type        = string
  default     = "nomad.example.internal"
}

variable "nomad_bootstrap_expect" {
  description = "Number of instances expected to bootstrap a new Nomad cluster"
  type        = number
  default     = 3
}

variable "nomad_gossip_encrypt_key" {
  description = "Gossip encryption key to use for Nomad servers"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "nomad_join_tag_value" {
  description = "Value of the tag used for Nomad server auto-join"
  type        = string
  nullable    = false
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
