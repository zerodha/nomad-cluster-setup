resource "aws_instance" "nomad_client" {
  count = var.client_type == "ec2" ? var.ec2_count : 0

  ami                     = var.ami
  instance_type           = data.aws_ec2_instance_type.type.instance_type
  iam_instance_profile    = var.iam_instance_profile == "" ? aws_iam_instance_profile.nomad_client[0].name : var.iam_instance_profile
  disable_api_termination = false
  subnet_id               = element(var.subnets, count.index)
  vpc_security_group_ids  = var.client_security_groups

  root_block_device {
    encrypted             = var.ebs_encryption
    delete_on_termination = true
    volume_size           = var.ebs_volume_size
    volume_type           = var.ebs_volume_type
    iops                  = var.ebs_iops
    tags = merge(
      {
        Name    = "${var.cluster_name}-client-${var.client_name}-root-${count.index + 1}"
        cluster = var.cluster_name
      },
      var.ebs_tags
    )
  }

  metadata_options {
    http_tokens                 = var.http_tokens
    http_endpoint               = "enabled"
    http_put_response_hop_limit = var.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  user_data_base64 = base64encode(data.cloudinit_config.config.rendered)

  tags = merge(
    {
      Name           = "${var.client_name}-${count.index + 1}"
      role           = "nomad-client"
      nomad_client   = var.client_name
      nomad_ec2_join = var.nomad_join_tag_value
    },
    var.ec2_tags
  )

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ami, user_data, user_data_base64]
  }
}
