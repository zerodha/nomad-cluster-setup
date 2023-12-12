resource "aws_launch_template" "nomad_server" {
  description             = "Launch template for nomad servers in ${var.cluster_name} cluster"
  disable_api_termination = false
  image_id                = var.ami
  instance_type           = data.aws_ec2_instance_type.type.instance_type
  name                    = "${var.cluster_name}-server"
  tags                    = {}
  vpc_security_group_ids  = concat(var.default_security_groups, [aws_security_group.nomad_agent.id])
  update_default_version  = true

  user_data = base64encode(templatefile("${path.module}/scripts/setup_server.tftpl.sh", {
    nomad_acl_bootstrap_token = var.nomad_acl_bootstrap_token
    nomad_acl_enable          = var.nomad_acl_enable
    enable_tls                = var.enable_tls
    tls_certificates          = var.tls_certificates
    tls_http_enable           = var.tls_http_enable
    tls_rpc_enable            = var.tls_rpc_enable
    nomad_server_cfg = templatefile("${path.module}/templates/nomad.tftpl", {
      nomad_dc                 = var.cluster_name
      aws_region               = var.aws_region
      nomad_bootstrap_expect   = var.nomad_bootstrap_expect
      nomad_gossip_encrypt_key = var.nomad_gossip_encrypt_key
      nomad_join_tag_key       = "nomad_ec2_join"
      nomad_join_tag_value     = var.nomad_join_tag_value
      nomad_acl_enable         = var.nomad_acl_enable
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
