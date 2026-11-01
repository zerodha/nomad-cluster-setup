mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      availability_zone = "ap-south-2a"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

# Plan only: prevent_destroy on data volumes blocks the teardown of an apply.
variables {
  ami                       = "ami-0123456789abcdef0"
  client_name               = "pg"
  cluster_name              = "test-nomad"
  cluster_tags              = { env = "test" }
  nomad_join_tag_value      = "test"
  route_53_resolver_address = "10.0.0.2"
  secrets_ssm_prefix        = "/nomad/example"
  subnets                   = ["subnet-0123456789abcdef0"]
  static_nodes = {
    "pg-1" = { subnet_id = "subnet-0123456789abcdef0", data_volume_size = 100 }
  }
}

run "static_nodes_replace_the_asg" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_group.nomad_client) == 0 && length(aws_instance.static) == 1
    error_message = "static_nodes must create instances instead of the ASG."
  }

  assert {
    condition     = aws_instance.static["pg-1"].disable_api_termination && aws_instance.static["pg-1"].tags["nomad_static_node"] == "pg-1"
    error_message = "Static nodes must have termination protection and their key as a tag."
  }

  assert {
    condition     = aws_ebs_volume.data["pg-1"].availability_zone == "ap-south-2a" && aws_ebs_volume.data["pg-1"].size == 100 && aws_ebs_volume.data["pg-1"].type == "gp3"
    error_message = "The data volume must be in the subnet's AZ with the requested size."
  }

  assert {
    condition     = aws_volume_attachment.data["pg-1"].stop_instance_before_detaching
    error_message = "The old instance must stop before its data volume is detached."
  }
}

run "data_volume_script_mounts_before_nomad" {
  command = plan

  # The volume ID is only known after apply, so this renders the template
  # directly. The live wiring is covered by the cloud-init part order.
  assert {
    condition = alltrue([
      for s in [
        "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0123456789abcdef0",
        "RequiresMountsFor=$MOUNT_PATH",
        "readonly MOUNT_PATH=\"/var/lib/nomad-data\"",
        "host_volume \"data\"",
        "static_node = \"pg-1\"",
        "name = \"pg-pg-1\"",
        "mkfs.xfs -L nomad-data",
        ] : strcontains(templatefile("${path.module}/scripts/data_volume.tftpl.sh", {
          volume_id   = "vol-0123456789abcdef0"
          mount_path  = "/var/lib/nomad-data"
          host_volume = "data"
          node_key    = "pg-1"
          node_name   = "pg-pg-1"
      }), s)
    ])
    error_message = "The data volume script must mount the volume and configure the host volume."
  }
}

run "asg_pools_are_unchanged" {
  command = plan

  variables {
    static_nodes = {}
  }

  assert {
    condition     = length(aws_autoscaling_group.nomad_client) == 1 && length(aws_instance.static) == 0 && length(aws_ebs_volume.data) == 0
    error_message = "Without static_nodes the module must create only the ASG."
  }
}

run "rejects_invalid_static_node_key" {
  command = plan

  variables {
    static_nodes = {
      "PG_1" = { subnet_id = "subnet-0123456789abcdef0", data_volume_size = 100 }
    }
  }

  expect_failures = [var.static_nodes]
}

run "adopted_volume_keeps_its_encryption_and_node_its_ip" {
  command = plan

  variables {
    static_nodes = {
      "pg-1" = {
        subnet_id             = "subnet-0123456789abcdef0"
        data_volume_size      = 100
        data_volume_encrypted = false
        private_ip            = "10.0.1.10"
      }
    }
  }

  assert {
    condition     = aws_ebs_volume.data["pg-1"].encrypted == false && aws_instance.static["pg-1"].private_ip == "10.0.1.10"
    error_message = "data_volume_encrypted and private_ip must reach the volume and the instance."
  }
}

run "data_volume_script_mounts_existing_filesystems_as_they_are" {
  command = plan

  assert {
    condition = alltrue([
      for s in [
        "fstype=$(blkid -p -s TYPE -o value \"$DEVICE\" || true)",
        "printf 'UUID=%s %s %s defaults,nofail 0 2\\n' \"$uuid\" \"$MOUNT_PATH\" \"$fstype\"",
        "refusing to touch it",
        ] : strcontains(templatefile("${path.module}/scripts/data_volume.tftpl.sh", {
          volume_id   = "vol-0123456789abcdef0"
          mount_path  = "/data"
          host_volume = "data"
          node_key    = "pg-1"
          node_name   = "pg-pg-1"
      }), s)
    ])
    error_message = "The script must mount an existing filesystem with its own type and refuse partitioned volumes."
  }
}

run "static_nodes_set_security_groups_on_the_instance" {
  command = plan

  variables {
    client_security_groups = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = aws_launch_template.nomad_client.vpc_security_group_ids == null && aws_instance.static["pg-1"].vpc_security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Static nodes must carry their security groups, not the launch template, so private_ip works."
  }
}
