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

  mock_resource "aws_lb_target_group" {
    defaults = {
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
  ami                  = "ami-0123456789abcdef0"
  cluster_name         = "test-nomad"
  cluster_tags         = { env = "test" }
  secrets_ssm_prefix   = "/nomad/example"
  nomad_join_tag_value = "test"
  vpc                  = "vpc-0123456789abcdef0"
  subnets              = ["subnet-0123456789abcdef0"]
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = length(aws_launch_template.nomad_server.user_data) > 0
    error_message = "Launch template user_data must not be empty."
  }

  assert {
    condition     = length(aws_lb.nomad) == 0
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
    condition     = length(aws_lb.nomad) == 1
    error_message = "ALB must be created when create_alb is true."
  }

  assert {
    condition     = length(aws_lb_listener.http) == 1 && length(aws_lb_listener.https) == 0
    error_message = "Without a certificate the ALB must only listen on HTTP."
  }
}

run "plans_with_alb_https" {
  command = plan

  variables {
    create_alb                = true
    alb_certificate_arn       = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    nomad_alb_hostname        = "nomad.example.test"
    nomad_server_incoming_ips = ["10.0.0.0/16"]
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http) == 0
    error_message = "With a certificate the ALB must only listen on HTTPS."
  }

  assert {
    condition     = flatten([for c in aws_lb_listener_rule.https_host[0].condition : c.host_header[0].values]) == ["nomad.example.test"]
    error_message = "The HTTPS rule must forward only the Nomad hostname."
  }
}

run "accepts_longest_cluster_name" {
  command = plan

  variables {
    cluster_name              = "abcdefghijklmnopqrstuvwxyz12"
    create_alb                = true
    nomad_server_incoming_ips = ["10.0.0.0/16"]
  }

  assert {
    condition     = aws_lb.nomad[0].name == "abcdefghijklmnopqrstuvwxyz12-web" && length(aws_lb.nomad[0].name) == 32
    error_message = "A 28 character cluster_name must give a 32 character ALB name."
  }
}

run "rejects_cluster_name_over_28_characters" {
  command = plan

  variables {
    cluster_name = "abcdefghijklmnopqrstuvwxyz123"
  }

  expect_failures = [var.cluster_name]
}

run "rejects_uppercase_cluster_name" {
  command = plan

  variables {
    cluster_name = "Demo"
  }

  expect_failures = [var.cluster_name]
}

run "rejects_cluster_name_with_trailing_hyphen" {
  command = plan

  variables {
    cluster_name = "demo-"
  }

  expect_failures = [var.cluster_name]
}
