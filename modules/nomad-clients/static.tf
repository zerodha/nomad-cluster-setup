# Static nodes are for stateful work, such as databases, that must not run in
# an ASG. Each node has its own EBS data volume that outlives the instance, so
# replacing a node (`tofu apply -replace`) re-attaches the same data.

data "aws_subnet" "static" {
  for_each = var.static_nodes
  id       = each.value.subnet_id
}

resource "aws_ebs_volume" "data" {
  for_each = var.static_nodes

  availability_zone = data.aws_subnet.static[each.key].availability_zone
  size              = each.value.data_volume_size
  type              = each.value.data_volume_type
  iops              = each.value.data_volume_iops
  throughput        = each.value.data_volume_throughput
  encrypted         = var.ebs_encryption
  kms_key_id        = var.data_volume_kms_key_arn

  tags = merge(
    var.cluster_tags,
    {
      Name              = "${var.cluster_name}-${var.client_name}-${each.key}-data"
      nomad_client      = var.client_name
      nomad_static_node = each.key
    },
    var.ebs_tags,
    var.data_volume_tags,
  )

  # Deleting a node's data takes a deliberate `tofu state rm` and a manual
  # delete, never a plan.
  lifecycle {
    prevent_destroy = true
  }
}

data "cloudinit_config" "static" {
  for_each = var.static_nodes

  gzip          = false
  base64_encode = false

  # cloud-init runs scripts in filename order, so 00-data-volume.sh mounts the
  # volume before setup_client.sh starts Nomad. The other parts match the ASG.
  part {
    filename     = "00-data-volume.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/scripts/data_volume.tftpl.sh", {
      volume_id   = aws_ebs_volume.data[each.key].id
      mount_path  = var.data_volume_mount_path
      host_volume = var.data_volume_host_volume
      node_key    = each.key
      node_name   = "${var.client_name}-${each.key}"
    })
  }

  part {
    filename     = "setup_client.sh"
    content_type = "text/x-shellscript"
    content      = local.setup_client
  }

  part {
    filename     = "extra_script.sh"
    content_type = "text/x-shellscript"
    merge_type   = "str(append)"
    content = var.extra_script_content != "" ? var.extra_script_content : (
      var.extra_script != "" ? file(var.extra_script) : "#!/bin/bash"
    )
  }
}

resource "aws_instance" "static" {
  for_each = var.static_nodes

  launch_template {
    id      = aws_launch_template.nomad_client.id
    version = aws_launch_template.nomad_client.latest_version
  }

  subnet_id               = each.value.subnet_id
  instance_type           = coalesce(each.value.instance_type, var.instance_type)
  user_data_base64        = base64encode(data.cloudinit_config.static[each.key].rendered)
  disable_api_termination = var.static_termination_protection

  tags = merge(
    var.cluster_tags,
    var.ec2_tags,
    {
      Name              = "${var.client_name}-${each.key}"
      role              = "nomad-client"
      nomad_client      = var.client_name
      nomad_ec2_join    = var.nomad_join_tag_value
      nomad_static_node = each.key
    },
  )

  # A stateful node is only replaced on purpose, with `tofu apply -replace`.
  # New AMIs and config reach it then; bootc updates the OS in place meanwhile.
  lifecycle {
    ignore_changes = [ami, launch_template, user_data, user_data_base64]

    # See the same check on the launch template.
    precondition {
      condition     = can(regex("^[[:ascii:]]*$", data.cloudinit_config.static[each.key].rendered))
      error_message = "User data must be ASCII. Check text inputs such as node meta, nomad_extra_config and extra scripts."
    }
  }
}

resource "aws_volume_attachment" "data" {
  for_each = var.static_nodes

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.static[each.key].id

  # Stops the old instance before detaching, so the filesystem is clean when
  # the replacement mounts it.
  stop_instance_before_detaching = true
}
