output "nomad_client_iam_profile" {
  description = "IAM Profile created for Nomad Client"
  value       = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].id : var.iam_instance_profile
}

output "nomad_client_asg" {
  description = "Autoscaling group for the Nomad client nodes"
  value       = one(aws_autoscaling_group.nomad_client[*].name)
}

output "static_nodes" {
  description = "Static nodes by key, with their instance ID, private IP and data volume ID"
  value = {
    for key, instance in aws_instance.static : key => {
      instance_id    = instance.id
      private_ip     = instance.private_ip
      data_volume_id = aws_ebs_volume.data[key].id
    }
  }
}

output "nomad_client_iam_role_arn" {
  description = "ARN of the IAM role for the Nomad client nodes"
  value       = var.iam_instance_profile == "" ? aws_iam_role.nomad_client[0].arn : ""
}

output "nomad_client_launch_template_id" {
  description = "ID of the launch template for the Nomad client nodes"
  value       = aws_launch_template.nomad_client.id
}
