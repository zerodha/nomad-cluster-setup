### Outputs

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = var.create_alb ? module.alb[0].lb_dns_name : ""
}

output "alb_security_group_id" {
  description = "The ID of the ALB security group"
  value       = var.create_alb ? aws_security_group.alb[0].id : ""
}

output "nomad_server_asg_name" {
  description = "The name of the Nomad server Auto Scaling Group"
  value       = aws_autoscaling_group.nomad_server.name
}

output "nomad_server_asg_arn" {
  description = "The ARN of the Nomad server Auto Scaling Group"
  value       = aws_autoscaling_group.nomad_server.arn
}

output "nomad_server_launch_template_id" {
  description = "The ID of the Nomad server launch template"
  value       = aws_launch_template.nomad_server.id
}

output "nomad_agent_security_group_id" {
  description = "The ID of the Nomad agent security group"
  value       = aws_security_group.nomad_agent.id
}

output "nomad_server_iam_role_arn" {
  description = "The ARN of the Nomad server IAM role"
  value       = aws_iam_role.nomad_server.arn
}
