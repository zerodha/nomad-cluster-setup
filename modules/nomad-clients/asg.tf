resource "aws_autoscaling_group" "nomad_client" {
  count = var.client_type == "asg" ? 1 : 0

  name                      = "${var.cluster_name}-${var.client_name}"
  max_size                  = var.instance_max_count
  min_size                  = var.instance_min_count
  desired_capacity          = var.instance_desired_count
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.healthcheck_type
  vpc_zone_identifier       = var.subnets
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  enabled_metrics           = var.autoscale_metrics
  termination_policies      = ["OldestInstance"]

  target_group_arns = var.target_group_arns

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.nomad_client[0].id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.override_instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

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
    value               = "nomad-client"
    propagate_at_launch = true
  }

  tag {
    key                 = "nomad_client"
    value               = var.client_name
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
