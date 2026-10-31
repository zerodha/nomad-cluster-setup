mock_provider "aws" {
  # The provider validates IAM policy JSON at plan time, so the mock must
  # return a syntactically valid document.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  ami                       = "ami-0123456789abcdef0"
  client_name               = "test"
  cluster_name              = "test-nomad"
  cluster_tags              = { env = "test" }
  nomad_join_tag_value      = "test"
  route_53_resolver_address = "10.0.0.2"
  vpc                       = "vpc-0123456789abcdef0"
  subnets                   = ["subnet-0123456789abcdef0"]
}

run "plans_asg_with_defaults" {
  command = plan

  assert {
    condition     = length(aws_launch_template.nomad_client[0].user_data) > 0
    error_message = "Launch template user_data must not be empty."
  }

  assert {
    condition     = length(aws_instance.nomad_client) == 0
    error_message = "No standalone EC2 instances must be planned in asg mode."
  }
}

run "plans_ec2_client" {
  command = plan

  variables {
    client_type = "ec2"
    ec2_count   = 2
  }

  assert {
    condition     = length(aws_instance.nomad_client) == 2
    error_message = "ec2 mode must plan ec2_count instances."
  }

  assert {
    condition     = length(aws_instance.nomad_client[0].user_data_base64) > 0
    error_message = "EC2 user_data must not be empty."
  }

  assert {
    condition     = length(aws_launch_template.nomad_client) == 0
    error_message = "No launch template must be planned in ec2 mode."
  }
}

run "rejects_cluster_name_without_suffix" {
  command = plan

  variables {
    cluster_name = "test"
  }

  expect_failures = [var.cluster_name]
}
