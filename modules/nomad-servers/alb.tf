module "alb" {
  count = var.create_alb ? 1 : 0

  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-web"

  load_balancer_type = "application"
  internal           = true

  vpc_id          = var.vpc
  subnets         = var.subnets
  security_groups = concat([aws_security_group.alb[0].id], var.nomad_server_incoming_security_groups)

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

  vpc_id = var.vpc
  tags = {
    Name = "${var.cluster_name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ir_alb" {
  count             = var.create_alb ? length(var.nomad_server_incoming_ips) : 0
  security_group_id = aws_security_group.alb[0].id
  description       = "Allow access to Nomad ALB"
  from_port         = var.alb_certificate_arn == "" ? 80 : 443
  to_port           = var.alb_certificate_arn == "" ? 80 : 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.nomad_server_incoming_ips[count.index]
}

resource "aws_vpc_security_group_egress_rule" "er_alb" {
  count             = var.create_alb ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  description       = "Allow all outgoing traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "er_alb_ipv6" {
  count             = var.create_alb ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  description       = "Allow all outgoing traffic (IPv6)"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}
