# This example sets up a 10-node nomad client setup in a cluster
# It also includes load balancer setup to connect to any applications
# running within the cluster

module "nomad_client_demo" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup//nomad-clients?ref=main"

  client_name               = "example-application"
  cluster_name              = "demo-nomad"
  enable_docker_plugin      = true
  instance_desired_count    = 10
  instance_type             = "c6a.xlarge"
  nomad_join_tag_value      = "demo"
  route_53_resolver_address = "10.0.0.2"

  client_security_groups = module.nomad_servers.nomad_server_sg

  ami     = "ami-abc"
  subnets = "subnet-xyz"
  vpc     = "vpc-xyz"

  # Set this to allow the ALB to connect to the "demo-nomad"
  # client nodes.
  #
  # This also requires a security group rule allowing the ALB
  # to access the `backend_port` specified in the ALB configuration.
  # The additional security group can be created and appended to the
  # `client_security_groups` list.
  target_group_arns = module.demo_client_alb.target_group_arns
}

# Set up an example load balancer to connect to applications
# running on the "demo-nomad" nomad clients
#
# By default, specifying `target_group_arns` will ensure that
# all the "demo-nomad" client nodes get added to the ALB target
# group. This setup is meant for High Availability (HA),
# where the application or the reverse proxy
# runs on all the nodes on this client
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

# Security Group for the demo-nomad-client ALB
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
