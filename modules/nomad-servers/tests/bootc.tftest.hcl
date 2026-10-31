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
  ami                  = "ami-0123456789abcdef0"
  cluster_name         = "test-nomad"
  cluster_tags         = { env = "test" }
  nomad_join_tag_value = "test"
  secrets_ssm_prefix   = "/nomad/example"
  vpc                  = "vpc-0123456789abcdef0"
  subnets              = ["subnet-0123456789abcdef0"]
}

run "renders_boot_config_without_secrets" {
  command = plan

  assert {
    condition     = strcontains(base64decode(aws_launch_template.nomad_server.user_data), "aws ssm get-parameter --region \"$AWS_REGION\"")
    error_message = "User data must read secrets from SSM at boot."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.nomad_server.user_data), "readonly SECRETS_SSM_PREFIX=\"/nomad/example\"")
    error_message = "User data must use the configured SSM prefix."
  }

  assert {
    condition     = !can(regex("encrypt\\s*=\\s*\"[A-Za-z0-9+/]{16,}", base64decode(aws_launch_template.nomad_server.user_data)))
    error_message = "User data must not contain a gossip key."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.nomad_server.user_data), "PRIVATE KEY")
    error_message = "User data must not contain key material."
  }

  assert {
    condition = alltrue([
      for s in ["ens5", "/lib/systemd", "sed -i", "169.254.169.254", "hostnamectl"] :
      !strcontains(base64decode(aws_launch_template.nomad_server.user_data), s)
    ])
    error_message = "User data must not depend on interface names, IMDS, or edit files under /usr."
  }

  assert {
    condition = alltrue([
      for s in [
        "rm -f /etc/nomad.d/nomad.hcl",
        "region     = \"global\"",
        "datacenter = \"test-nomad\"",
        "bootstrap_expect = 3",
        "leave_on_terminate = true",
        "provider=aws region=eu-west-1 tag_key=nomad_ec2_join tag_value=test",
        "/etc/systemd/system/nomad.service.d/nomad-cluster-setup.conf",
        "LimitNOFILE=900000",
      ] : strcontains(base64decode(aws_launch_template.nomad_server.user_data), s)
    ])
    error_message = "User data is missing expected server configuration."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.nomad_server.user_data), "tls.hcl")
    error_message = "TLS configuration must only be written when tls_enabled is true."
  }

  assert {
    condition     = one(aws_launch_template.nomad_server.block_device_mappings).device_name == "/dev/xvda"
    error_message = "The root volume must use the AMI's root device name."
  }

  assert {
    condition     = one(aws_launch_template.nomad_server.metadata_options).http_tokens == "required"
    error_message = "IMDSv2 must be required by default."
  }

  assert {
    condition     = one(aws_launch_template.nomad_server.metadata_options).http_put_response_hop_limit == 1
    error_message = "The IMDS hop limit must default to 1."
  }
}

run "scopes_instance_policy_to_prefix" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_server.policy).Statement[0].Resource == "arn:aws:ssm:eu-west-1:123456789012:parameter/nomad/example/*"
    error_message = "SSM access must be limited to the secrets prefix."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_server.policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "ssm.eu-west-1.amazonaws.com"
    error_message = "KMS decrypt must only be allowed through SSM."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_server.policy).Statement[1].Resource == "*"
    error_message = "KMS decrypt must not be scoped to a key unless kms_key_arn is set."
  }
}

run "scopes_kms_to_customer_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.nomad_server.policy).Statement[1].Resource == "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "KMS decrypt must be scoped to kms_key_arn when set."
  }
}

run "reads_tls_material_from_ssm" {
  command = plan

  variables {
    tls_enabled     = true
    tls_http_enable = true
  }

  assert {
    condition = alltrue([
      for s in [
        "fetch_secret tls/ca_cert /etc/nomad.d/tls/ca.pem",
        "fetch_secret tls/cert /etc/nomad.d/tls/cert.pem",
        "fetch_secret tls/key /etc/nomad.d/tls/key.pem",
        "key_file  = \"/etc/nomad.d/tls/key.pem\"",
        "NOMAD_TLS_SERVER_NAME=server.global.nomad",
      ] : strcontains(base64decode(aws_launch_template.nomad_server.user_data), s)
    ])
    error_message = "TLS material must be read from SSM and referenced by absolute path."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.nomad_server.user_data), "PRIVATE KEY")
    error_message = "User data must not contain key material."
  }
}

run "skips_acl_bootstrap_when_acls_are_disabled" {
  command = plan

  variables {
    nomad_acl_enable = false
  }

  assert {
    condition = alltrue([
      for s in ["acl_bootstrap_token", "bootstrap_acl"] :
      !strcontains(base64decode(aws_launch_template.nomad_server.user_data), s)
    ])
    error_message = "The ACL token must not be read or used when ACLs are disabled."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.nomad_server.user_data), "enabled = false")
    error_message = "ACLs must be disabled in the agent configuration."
  }
}

run "derives_bootstrap_expect_and_datacenter" {
  command = plan

  variables {
    instance_count   = 5
    nomad_region     = "example"
    nomad_datacenter = "dc1"
  }

  assert {
    condition = alltrue([
      for s in ["bootstrap_expect = 5", "region     = \"example\"", "datacenter = \"dc1\""] :
      strcontains(base64decode(aws_launch_template.nomad_server.user_data), s)
    ])
    error_message = "bootstrap_expect, region and datacenter must follow the inputs."
  }
}

run "rejects_prefix_without_leading_slash" {
  command = plan

  variables {
    secrets_ssm_prefix = "nomad/example"
  }

  expect_failures = [var.secrets_ssm_prefix]
}

run "rejects_prefix_with_trailing_slash" {
  command = plan

  variables {
    secrets_ssm_prefix = "/nomad/example/"
  }

  expect_failures = [var.secrets_ssm_prefix]
}
