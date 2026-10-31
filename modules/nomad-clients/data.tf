# Set to ensure instance type exists
data "aws_ec2_instance_type" "type" {
  instance_type = var.instance_type
}

data "aws_ami" "nomad" {
  filter {
    name   = "image-id"
    values = [var.ami]
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

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
