module "alb" {
  count = var.create_alb ? 1 : 0

  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-web"

  load_balancer_type = "application"
  internal           = true

  vpc_id          = var.vpc
  subnets         = var.subnets
  security_groups = [aws_security_group.alb[0].id]

  target_groups = [
    {
      name_prefix      = "nomad-"
      backend_protocol = "HTTP"
      backend_port     = 4646
      target_type      = "instance"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/ui/"
        port                = "traffic-port"
        healthy_threshold   = 5
        unhealthy_threshold = 2
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200"
      }
    }
  ]

  https_listeners = var.alb_certificate_arn == "" ? [] : [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = var.alb_certificate_arn
      target_group_index = 0

      action_type = "fixed-response"
      fixed_response = {
        content_type = "text/plain"
        status_code  = "404"
      }
    }
  ]

  https_listener_rules = var.alb_certificate_arn == "" ? [] : [
    {
      https_listener_index = 0
      actions = [{
        type               = "forward"
        target_group_index = 0
      }]
      conditions = [{
        host_headers = ["${var.nomad_alb_hostname}"]
      }]
    }
  ]

  http_tcp_listeners = var.alb_certificate_arn != "" ? [] : [
    {
      port     = 80
      protocol = "HTTP"
    }
  ]

  http_tcp_listener_rules = var.alb_certificate_arn != "" ? [] : [
    {
      http_tcp_listener_index = 0
      actions = [{
        type               = "forward"
        target_group_index = 0
      }]

      conditions = [{
        host_headers = ["${var.nomad_alb_hostname}"]
      }]
    }
  ]

  tags = {
    Name = "${var.cluster_name}-web"
  }
}

resource "aws_security_group" "alb" {
  count = var.create_alb ? 1 : 0

  name        = "${var.cluster_name}-alb"
  description = "Security Group for ${var.cluster_name} ALB"
  ingress = [
    {
      description      = "Allow access to Nomad ALB"
      from_port        = var.alb_certificate_arn == "" ? 80 : 443
      to_port          = var.alb_certificate_arn == "" ? 80 : 443
      cidr_blocks      = var.nomad_server_incoming_ips
      ipv6_cidr_blocks = []
      security_groups  = var.nomad_server_incoming_security_groups
      prefix_list_ids  = []
      self             = false
      protocol         = "tcp"
    }
  ]

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

  vpc_id = var.vpc
  tags = {
    Name = "${var.cluster_name}-alb"
  }
}
