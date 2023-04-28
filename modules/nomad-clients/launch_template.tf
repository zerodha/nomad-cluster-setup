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

  user_data = base64encode(templatefile("${path.module}/scripts/setup_client.tftpl.sh", {
    route_53_resolver_address = var.route_53_resolver_address
    enable_docker_plugin      = var.enable_docker_plugin
    nomad_join_tag_key        = "nomad_ec2_join"
    nomad_join_tag_value      = var.nomad_join_tag_value
    nomad_client_cfg = templatefile("${path.module}/templates/nomad.tftpl.hcl", {
      nomad_dc = var.cluster_name
    })
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
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
      Name = "${var.cluster_name}-client-${var.client_name}"
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
}
