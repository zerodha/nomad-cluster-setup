resource "aws_autoscaling_group" "nomad_server" {
  launch_template {
    id      = aws_launch_template.nomad_server.id
    version = "$Latest"
  }

  name                      = "${var.cluster_name}-server"
  max_size                  = var.instance_count
  min_size                  = var.instance_count
  desired_capacity          = var.instance_count
  health_check_grace_period = 60
  health_check_type         = "EC2"
  vpc_zone_identifier       = var.subnets
  wait_for_capacity_timeout = "10m"
  enabled_metrics           = var.autoscale_metrics
  termination_policies      = ["OldestInstance"]

  target_group_arns = var.create_alb ? module.alb[0].target_group_arns : []

  dynamic "tag" {
    for_each = var.cluster_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "role"
    value               = "nomad-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "nomad_ec2_join"
    value               = var.nomad_join_tag_value
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
}
