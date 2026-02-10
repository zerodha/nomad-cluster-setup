locals {
    setup_server = templatefile("${path.module}/scripts/setup_server.tftpl.sh", {
    nomad_acl_bootstrap_token = var.nomad_acl_bootstrap_token
    nomad_acl_enable          = var.nomad_acl_enable
    nomad_file_limit          = var.nomad_file_limit
    nomad_dc                  = var.cluster_name
    nomad_raft_backup_bucket  = var.nomad_raft_backup_bucket

    nomad_server_cfg = templatefile("${path.module}/templates/nomad.tftpl", {
      nomad_dc                 = var.cluster_name
      aws_region               = var.aws_region
      nomad_bootstrap_expect   = var.nomad_bootstrap_expect
      nomad_gossip_encrypt_key = var.nomad_gossip_encrypt_key
      nomad_join_tag_key       = "nomad_ec2_join"
      nomad_join_tag_value     = var.nomad_join_tag_value
      nomad_acl_enable         = var.nomad_acl_enable
    })
    nomad_file_limit = var.nomad_file_limit
  })
}
