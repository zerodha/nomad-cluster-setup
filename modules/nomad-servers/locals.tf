locals {
    setup_server = templatefile("${path.module}/scripts/setup_server.tftpl.sh", {
    nomad_acl_bootstrap_token = var.nomad_acl_bootstrap_token
    nomad_acl_enable          = var.nomad_acl_enable
    nomad_file_limit          = var.nomad_file_limit
    nomad_dc                  = var.cluster_name
    nomad_raft_backup_bucket  = var.nomad_raft_backup_bucket

    nomad_server_cfg = templatefile("${path.module}/templates/nomad.tftpl", {
      nomad_dc                        = var.cluster_name
      aws_region                      = var.aws_region
      nomad_bootstrap_expect          = var.nomad_bootstrap_expect
      nomad_gossip_encrypt_key        = var.nomad_gossip_encrypt_key
      nomad_join_tag_key              = "nomad_ec2_join"
      nomad_join_tag_value            = var.nomad_join_tag_value
      nomad_acl_enable                = var.nomad_acl_enable
      enable_mem_oversubscription     = var.enable_mem_oversubscription
      nomad_http_max_conns_per_client = var.http_max_conns_per_client
      nomad_job_gc_threshold          = var.nomad_job_gc_threshold
    })
    nomad_file_limit = var.nomad_file_limit
  })
}
