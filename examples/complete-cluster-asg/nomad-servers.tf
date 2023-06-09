# This example sets up a 3 node terraform server in a cluster
# Ensure that all the clients that need to connect to this cluster
# use the same `nomad_join_tag_value`

module "nomad_servers" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup//nomad-servers?ref=main"

  instance_count = 3

  cluster_name         = "demo-nomad"
  create_alb           = true
  nomad_alb_hostname   = "nomad.example.internal"
  nomad_join_tag_value = "demo"

  ami     = "ami-xyz"
  vpc     = "vpc-xyz"
  subnets = "subnet-xyz"

  nomad_gossip_encrypt_key  = var.nomad_gossip_encrypt_key
  nomad_acl_bootstrap_token = var.nomad_acl_bootstrap_token
}
