# Set to ensure instance type exists
data "aws_ec2_instance_type" "type" {
  instance_type = var.instance_type
}

data "cloudinit_config" "config" {
  gzip = false
  base64_encode = false

  part {
    filename = "setup_client.sh"
    content_type = "text/x-shellscript"
    content = local.setup_client
  }

  part {
    filename = "extra_script.sh"
    content_type = "text/x-shellscript"
    merge_type   = "str(append)"
    content = var.extra_script != "" ? file(var.extra_script) : "#!/bin/bash"
  }
}