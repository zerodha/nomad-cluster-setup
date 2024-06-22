resource "aws_launch_template" "nomad_server" {
  description             = "Launch template for nomad servers in ${var.cluster_name} cluster"
  disable_api_termination = false
  image_id                = var.ami
  instance_type           = data.aws_ec2_instance_type.type.instance_type
  name                    = "${var.cluster_name}-server"
  tags                    = {}
  vpc_security_group_ids  = concat(var.default_security_groups, [aws_security_group.nomad_agent.id])
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
      volume_size           = 100
      volume_type           = "gp3"
    }
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.nomad_server.name
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.cluster_name}-server"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      {
        Name = "${var.cluster_name}-server"
      },
      var.ebs_tags
    )
  }
}
