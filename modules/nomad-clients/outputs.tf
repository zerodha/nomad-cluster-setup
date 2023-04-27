output "nomad_client_iam_profile" {
  description = "IAM Profile created for Nomad Client"
  value       = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].id : var.iam_instance_profile
}

output "asg_name" {
  description = "Autoscaling group created for Nomad client nodes (when client_type is 'asg')"
  value       = var.client_type == "asg" ? aws_autoscaling_group.nomad_client[0].name : ""
}
