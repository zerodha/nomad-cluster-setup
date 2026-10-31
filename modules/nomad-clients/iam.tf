# IAM roles, policies that apply to Nomad client role.

# This assume role policy is applied to all EC2 instances.
data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nomad_client" {
  count              = var.iam_instance_profile == "" ? 1 : 0
  name               = "${var.cluster_name}-${var.client_name}"
  tags               = var.iam_tags
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json

  lifecycle {
    precondition {
      condition     = length("${var.cluster_name}-${var.client_name}") <= 64
      error_message = "The IAM role name \"<cluster_name>-<client_name>\" must be at most 64 characters. Shorten cluster_name or client_name, or set iam_instance_profile."
    }
  }
}

resource "aws_iam_role_policy" "nomad_client" {
  count  = var.iam_instance_profile == "" ? 1 : 0
  name   = "${var.cluster_name}-${var.client_name}"
  role   = aws_iam_role.nomad_client[0].id
  policy = local.instance_policy
}

resource "aws_iam_role_policy_attachment" "default_iam_policies" {
  for_each   = var.iam_instance_profile == "" ? toset(var.iam_policy_arns) : []
  role       = aws_iam_role.nomad_client[0].name
  policy_arn = each.key
}

resource "aws_iam_instance_profile" "nomad_client" {
  count = var.iam_instance_profile == "" ? 1 : 0
  name  = "${var.cluster_name}-${var.client_name}"
  role  = aws_iam_role.nomad_client[0].id
}
