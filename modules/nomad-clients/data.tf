# Set to ensure instance type exists
data "aws_ec2_instance_type" "type" {
  instance_type = var.instance_type
}
