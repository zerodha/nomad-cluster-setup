# This example sets up a 3 node Nomad server cluster.
# Ensure that all the clients that need to connect to this cluster
# use the same `nomad_join_tag_value`.
#
# Before applying, store the cluster secrets as SecureString parameters:
#
#   aws ssm put-parameter --type SecureString --name /nomad/example/gossip_key --value "$(nomad operator gossip keyring generate)"
#   aws ssm put-parameter --type SecureString --name /nomad/example/acl_bootstrap_token --value "$(uuidgen)"

module "nomad_servers" {
  source = "../../modules/nomad-servers"

  instance_count = 3

  cluster_name         = "demo-nomad"
  cluster_tags         = { env = "demo" }
  create_alb           = true
  nomad_alb_hostname   = "nomad.example.com"
  nomad_join_tag_value = "demo"
  secrets_ssm_prefix   = "/nomad/example"

  ami     = "ami-0123456789abcdef0"
  vpc     = "vpc-0123456789abcdef0"
  subnets = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
}
