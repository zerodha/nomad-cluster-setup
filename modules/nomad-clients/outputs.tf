output "nomad_client_iam_profile" {
  description = "IAM Profile created for Nomad Client"
  value       = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].id : var.iam_instance_profile
}

output "nomad_client_asg" {
  description = "Autoscaling group for the Nomad client nodes"
  value       = var.client_type == "asg" ? aws_autoscaling_group.nomad_client[0].name : ""
}

output "nomad_client_iam_role_arn" {
  description = "ARN of the IAM role for the Nomad client nodes"
  value       = var.iam_instance_profile == "" ? aws_iam_role.nomad_client[0].arn : ""
}

output "nomad_client_launch_template_id" {
  description = "ID of the launch template for the Nomad client nodes"
  value       = var.client_type == "asg" ? aws_launch_template.nomad_client[0].id : ""
}
