mock_provider "aws" {
  # The provider validates IAM policy JSON at plan time, so the mock must
  # return a syntactically valid document.
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

  # ALB listeners validate the load balancer and target group ARNs at plan time.
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/0123456789abcdef"
    }
  }

  # The upstream module references the target group by id, which AWS sets to the ARN.
  mock_resource "aws_lb_target_group" {
    defaults = {
      id  = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/0123456789abcdef"
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/0123456789abcdef/0123456789abcdef"
    }
  }
}

variables {
  ami                      = "ami-0123456789abcdef0"
  cluster_name             = "test-nomad"
  cluster_tags             = { env = "test" }
  nomad_gossip_encrypt_key = "dGVzdC1nb3NzaXAta2V5LTMyLWJ5dGVzLWxvbmchIQ=="
  nomad_join_tag_value     = "test"
  vpc                      = "vpc-0123456789abcdef0"
  subnets                  = ["subnet-0123456789abcdef0"]
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = length(aws_launch_template.nomad_server.user_data) > 0
    error_message = "Launch template user_data must not be empty."
  }

  assert {
    condition     = length(module.alb) == 0
    error_message = "ALB must not be created by default."
  }
}

run "plans_with_alb" {
  command = plan

  variables {
    create_alb                = true
    nomad_server_incoming_ips = ["10.0.0.0/16"]
  }

  assert {
    condition     = length(module.alb) == 1
    error_message = "ALB must be created when create_alb is true."
  }
}

run "rejects_cluster_name_without_suffix" {
  command = plan

  variables {
    cluster_name = "test"
  }

  expect_failures = [var.cluster_name]
}
