module "nomad_client_demo" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup//nomad-clients?ref=main"

  client_name               = "example-application"
  cluster_name              = "demo-nomad"
  enable_docker_plugin      = true
  instance_desired_count    = 10
  instance_type             = "c6a.xlarge"
  nomad_join_tag_value      = "demo"
  route_53_resolver_address = "10.0.0.2"

  ami     = "ami-abc"
  subnets = "subnet-xyz"
  vpc     = "vpc-xyz"
}


module "demo_client_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.2.1"

  name = "demo-nomad-client-alb"

  load_balancer_type = "application"
  internal           = false

  vpc_id          = "vpc-xyz"
  subnets         = ["subnet-abc", "subnet-xyz"]
  security_groups = [aws_security_group.demo_client_nomad.id, "sg-12345678"]

  target_groups = [
    {
      name_prefix      = "nomad-"
      backend_protocol = "HTTP"
      backend_port     = 80 # This is where the reverse proxy runs on nomad
      target_type      = "instance"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 5
        unhealthy_threshold = 2
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200"
      }
    },
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Name = "demo-nomad-client-alb"
  }
}

resource "aws_security_group" "demo_client_nomad" {

  name        = "demo-client-nomad-alb"
  description = "ALB SG for demo-client-nomad"
  vpc_id      = "vpc-xyz"

  ingress = []
  egress = [
    {
      description      = "Allow all outgoing traffic"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  tags = {
    Name = "demo-client-nomad-alb"
  }
}
