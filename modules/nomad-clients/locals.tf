locals {
  setup_client = templatefile("${path.module}/scripts/setup_client.tftpl.sh", {
    aws_region                     = var.aws_region
    route_53_resolver_address      = var.route_53_resolver_address
    enable_docker_plugin           = var.enable_docker_plugin
    nomad_join_tag_key             = "nomad_ec2_join"
    nomad_join_tag_value           = var.nomad_join_tag_value
    nomad_file_limit               = var.nomad_file_limit
    nomad_client_exec_host_volumes = var.nomad_client_exec_host_volumes
    nomad_client_cfg = templatefile("${path.module}/templates/nomad.tftpl", {
      nomad_dc         = var.cluster_name
      nomad_acl_enable = var.nomad_acl_enable
    })
  })
}
