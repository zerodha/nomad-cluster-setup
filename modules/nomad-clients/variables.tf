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

variable "client_type" {
  description = "Type of client to deploy: 'ec2' or 'asg'"
  type        = string
  default     = "asg"
  nullable    = false

  validation {
    condition     = contains(["ec2", "asg"], var.client_type)
    error_message = "Client type can only be 'ec2' or 'asg'"
  }
}

variable "cluster_name" {
  description = "Identifier used for naming all resources associated with the cluster"
  type        = string
  nullable    = false
  validation {
    condition     = endswith(var.cluster_name, "-nomad")
    error_message = "The cluster_name value must be suffixed with '-nomad'"
  }
}

variable "default_iam_policies" {
  description = "List of IAM policies to assign to the Nomad clients"
  type        = list(string)
  default     = []
}

variable "ebs_volume_size" {
  description = "The size of the EBS volume in gigabytes"
  type        = number
  default     = 100
}

variable "ebs_tags" {
  description = "A map of custom tags to be assigned to the EBS volumes"
  type        = map(string)
  default     = {}
}

variable "enable_docker_plugin" {
  description = "Whether to enable the Docker plugin on the client nodes"
  type        = bool
  default     = true
}

variable "iam_instance_profile" {
  description = "Name of the existing IAM Instance Profile to use"
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

variable "vpc" {
  description = "AWS Virtual Private Cloud (VPC) to deploy all resources in"
  type        = string
  nullable    = false
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

variable "ec2_count" {
  description = "Number of Nomad client EC2 instances to run"
  type        = number
  default     = 1
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
