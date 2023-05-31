resource "aws_instance" "nomad_client" {
  count = var.client_type == "ec2" ? var.ec2_count : 0

  ami                     = var.ami
  instance_type           = data.aws_ec2_instance_type.type.instance_type
  iam_instance_profile    = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].name : var.iam_instance_profile
  disable_api_termination = false
  subnet_id               = element(var.subnets, count.index)
  vpc_security_group_ids  = var.client_security_groups

  root_block_device {
    delete_on_termination = true
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    tags = merge(
      {
        Name    = "${var.cluster_name}-client-${var.client_name}-root-${count.index + 1}"
        cluster = var.cluster_name
      },
      var.ebs_tags
    )
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data_base64 = base64encode(templatefile("${path.module}/scripts/setup_client.tftpl.sh", {
    route_53_resolver_address = var.route_53_resolver_address
    enable_docker_plugin      = var.enable_docker_plugin
    nomad_join_tag_key        = "nomad_ec2_join"
    nomad_join_tag_value      = var.nomad_join_tag_value
    nomad_client_cfg = templatefile("${path.module}/templates/nomad.tftpl", {
      nomad_dc         = var.cluster_name
      nomad_acl_enable = var.nomad_acl_enable
    })
  }))

  tags = {
    Name           = "${var.cluster_name}-client-${var.client_name}-${count.index + 1}"
    role           = "nomad-client"
    nomad_client   = var.client_name
    nomad_ec2_join = var.nomad_join_tag_value
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ami, user_data, user_data_base64]
  }
}
