locals {
  alb_https = var.create_alb && var.alb_certificate_arn != ""
  alb_http  = var.create_alb && var.alb_certificate_arn == ""
}

resource "aws_lb" "nomad" {
  count = var.create_alb ? 1 : 0

  name               = "${var.cluster_name}-web"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.subnets
  security_groups    = concat([aws_security_group.alb[0].id], var.nomad_server_incoming_security_groups)

  tags = {
    Name = "${var.cluster_name}-web"
  }
}

resource "aws_lb_target_group" "nomad" {
  count = var.create_alb ? 1 : 0

  name_prefix = "nomad-"
  port        = 4646
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc

  health_check {
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

  tags = {
    Name = "${var.cluster_name}-web"
  }

  # AWS refuses to delete a target group that a listener still uses, so a
  # replacement must exist first.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  count = local.alb_https ? 1 : 0

  load_balancer_arn = aws_lb.nomad[0].arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # Only requests for the Nomad hostname reach the servers.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "404"
    }
  }

  tags = {
    Name = "${var.cluster_name}-web"
  }
}

resource "aws_lb_listener_rule" "https_host" {
  count = local.alb_https ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad[0].arn
  }

  condition {
    host_header {
      values = [var.nomad_alb_hostname]
    }
  }

  tags = {
    Name = "${var.cluster_name}-web"
  }
}

resource "aws_lb_listener" "http" {
  count = local.alb_http ? 1 : 0

  load_balancer_arn = aws_lb.nomad[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad[0].arn
  }

  tags = {
    Name = "${var.cluster_name}-web"
  }
}

# Addresses created by terraform-aws-modules/alb/aws v6. The v6 HTTP host-header
# rule is not carried over because the HTTP listener already forwards all
# traffic to the same target group.
moved {
  from = module.alb[0].aws_lb.this[0]
  to   = aws_lb.nomad[0]
}

moved {
  from = module.alb[0].aws_lb_target_group.main[0]
  to   = aws_lb_target_group.nomad[0]
}

moved {
  from = module.alb[0].aws_lb_listener.frontend_https[0]
  to   = aws_lb_listener.https[0]
}

moved {
  from = module.alb[0].aws_lb_listener_rule.https_listener_rule[0]
  to   = aws_lb_listener_rule.https_host[0]
}

moved {
  from = module.alb[0].aws_lb_listener.frontend_http_tcp[0]
  to   = aws_lb_listener.http[0]
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
