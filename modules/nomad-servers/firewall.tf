
# ---
# Common security group for both Nomad server and clients.
# ---

resource "aws_security_group" "nomad_agent" {
  name        = "${var.cluster_name}-agent"
  description = "Security Group for Nomad agents - ${title(var.cluster_name)}"
  # description = "Nomad Agent Security Group for cluster ${title(var.cluster_name)}"
  vpc_id = var.vpc

  ingress = flatten([
    var.create_alb ? [
      {
        description      = "Allow ALB to access Nomad"
        from_port        = 4646
        to_port          = 4646
        cidr_blocks      = []
        ipv6_cidr_blocks = []
        security_groups  = [aws_security_group.alb[0].id]
        prefix_list_ids  = []
        self             = false
        protocol         = "tcp"
      }
    ] : [],
    [
      {
        description      = "Allow nomad agents to talk to each other on all ports"
        from_port        = 0
        to_port          = 0
        cidr_blocks      = []
        ipv6_cidr_blocks = []
        security_groups  = []
        prefix_list_ids  = []
        self             = true
        protocol         = "-1"
      }
    ]
  ])

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
    Name = "${var.cluster_name}-agent"
  }
}
