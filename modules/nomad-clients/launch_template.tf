resource "aws_launch_template" "nomad_client" {
  count                   = var.client_type == "asg" ? 1 : 0
  description             = "Launch template for nomad client ${var.client_name} in ${var.cluster_name} cluster"
  disable_api_termination = false
  image_id                = var.ami
  instance_type           = data.aws_ec2_instance_type.type.instance_type
  name                    = "${var.cluster_name}-client-${var.client_name}"
  tags                    = {}
  vpc_security_group_ids  = concat(var.client_security_groups)
  update_default_version  = true

  user_data = base64encode(data.cloudinit_config.config.rendered)

  metadata_options {
    http_tokens                 = var.http_tokens
    http_endpoint               = "enabled"
    http_put_response_hop_limit = var.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted             = var.ebs_encryption
      delete_on_termination = true
      volume_size           = var.ebs_volume_size
      volume_type           = var.ebs_volume_type
      iops                  = var.ebs_iops
    }
  }
  iam_instance_profile {
    name = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].name : var.iam_instance_profile
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = var.client_name
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      {
        Name = "${var.cluster_name}-client-${var.client_name}"
      },
      var.ebs_tags
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}
