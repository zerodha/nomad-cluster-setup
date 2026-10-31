mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      root_device_name = "/dev/xvda"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  # The provider validates IAM policy JSON at plan time.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # The ASG validates the launch template ID format at plan time.
  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-0123456789abcdef0"
    }
  }
}

variables {
  ami                       = "ami-0123456789abcdef0"
  client_name               = "app"
  cluster_name              = "test-nomad"
  cluster_tags              = { env = "test" }
  nomad_join_tag_value      = "test"
  route_53_resolver_address = "10.0.0.2"
  secrets_ssm_prefix        = "/nomad/example"
  vpc                       = "vpc-0123456789abcdef0"
  subnets                   = ["subnet-0123456789abcdef0"]
}

run "renders_boot_config_without_secrets" {
  command = plan

  assert {
    condition = alltrue([
      for s in ["ens5", "/lib/systemd", "sed -i", "169.254.169.254", "hostnamectl", "authorized_keys", "PRIVATE KEY", "/lib32", "/etc/timezone"] :
      !strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), s)
    ])
    error_message = "User data must not depend on interface names, IMDS, SSH users, or edit files under /usr."
  }

  assert {
    condition = alltrue([
      for s in [
        "rm -f /etc/nomad.d/nomad.hcl",
        "region     = \"global\"",
        "datacenter = \"test-nomad\"",
        "node_pool = \"default\"",
        "leave_on_interrupt = true",
        "deadline = \"5m\"",
        "provider=aws region=eu-west-1 tag_key=nomad_ec2_join tag_value=test",
        "\"ec2_nomad_client\" = \"app\"",
        "\"ec2_env\" = \"test\"",
        "\"/etc/pki\"",
        "search eu-west-1.compute.internal",
        "After=docker.service",
        "LimitNOFILE=900000",
        "TimeoutStopSec=5m 30s",
      ] : strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), s)
    ])
    error_message = "User data is missing expected client configuration."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), "fetch_secret tls/")
    error_message = "TLS material must only be read when tls_enabled is true."
  }

  assert {
    condition     = one(aws_launch_template.nomad_client[0].block_device_mappings).device_name == "/dev/xvda"
    error_message = "The root volume must use the AMI's root device name."
  }

  assert {
    condition     = one(aws_launch_template.nomad_client[0].metadata_options).http_tokens == "required"
    error_message = "IMDSv2 must be required by default."
  }

  assert {
    condition     = one(aws_launch_template.nomad_client[0].metadata_options).http_put_response_hop_limit == 1
    error_message = "The IMDS hop limit must default to 1."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_client[0].policy).Statement[0].Resource == "arn:aws:ssm:eu-west-1:123456789012:parameter/nomad/example/*"
    error_message = "SSM access must be limited to the secrets prefix."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_client[0].policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "ssm.eu-west-1.amazonaws.com"
    error_message = "KMS decrypt must only be allowed through SSM."
  }
}

run "reads_tls_material_from_ssm" {
  command = plan

  variables {
    tls_enabled = true
  }

  assert {
    condition = alltrue([
      for s in [
        "fetch_secret tls/ca_cert /etc/nomad.d/tls/ca.pem",
        "fetch_secret tls/cert /etc/nomad.d/tls/cert.pem",
        "fetch_secret tls/key /etc/nomad.d/tls/key.pem",
        "key_file  = \"/etc/nomad.d/tls/key.pem\"",
      ] : strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), s)
    ])
    error_message = "TLS material must be read from SSM and referenced by absolute path."
  }
}

run "follows_pool_drain_and_region_inputs" {
  command = plan

  variables {
    node_pool            = "batch"
    drain_deadline       = "1h30m"
    enable_docker_plugin = false
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  assert {
    condition = alltrue([
      for s in ["node_pool = \"batch\"", "deadline = \"1h30m\"", "TimeoutStopSec=1h30m 30s", "search ec2.internal"] :
      strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), s)
    ])
    error_message = "node_pool, drain_deadline and the DNS search domain must follow the inputs."
  }

  assert {
    condition = alltrue([
      for s in ["plugin \"docker\"", "After=docker.service"] :
      !strcontains(base64decode(aws_launch_template.nomad_client[0].user_data), s)
    ])
    error_message = "Docker settings must only be rendered when the Docker plugin is enabled."
  }
}

run "skips_inline_policy_for_external_profile" {
  command = plan

  variables {
    iam_instance_profile = "example-profile"
  }

  assert {
    condition     = length(aws_iam_role_policy.nomad_client) == 0
    error_message = "No inline policy must be created when an external instance profile is used."
  }
}

run "rejects_invalid_drain_deadline" {
  command = plan

  variables {
    drain_deadline = "5 minutes"
  }

  expect_failures = [var.drain_deadline]
}

run "rejects_reserved_node_pool" {
  command = plan

  variables {
    node_pool = "all"
  }

  expect_failures = [var.node_pool]
}

run "rejects_prefix_with_trailing_slash" {
  command = plan

  variables {
    secrets_ssm_prefix = "/nomad/example/"
  }

  expect_failures = [var.secrets_ssm_prefix]
}
