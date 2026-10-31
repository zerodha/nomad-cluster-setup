locals {
  aws_region       = data.aws_region.current.name
  nomad_datacenter = coalesce(var.nomad_datacenter, var.cluster_name)

  # Instance tags known at plan time, exposed as node meta with the same
  # "ec2_" keys that earlier versions read from instance metadata at boot.
  node_meta = {
    for key, value in merge(var.cluster_tags, var.ec2_tags, {
      role           = "nomad-client"
      nomad_client   = var.client_name
      nomad_ec2_join = var.nomad_join_tag_value
    }) : "ec2_${replace(key, ":", "_")}" => value
  }

  setup_client = templatefile("${path.module}/scripts/setup_client.tftpl.sh", {
    aws_region                = local.aws_region
    secrets_ssm_prefix        = var.secrets_ssm_prefix
    route_53_resolver_address = var.route_53_resolver_address
    dns_search_domain         = local.aws_region == "us-east-1" ? "ec2.internal" : "${local.aws_region}.compute.internal"
    docker_enabled            = var.enable_docker_plugin
    nomad_file_limit          = var.nomad_file_limit
    drain_deadline            = var.drain_deadline
    host_volumes              = values(var.nomad_client_exec_host_volumes)
    tls_enabled               = var.tls_enabled

    base_hcl = templatefile("${path.module}/templates/base.hcl.tftpl", {
      nomad_region     = var.nomad_region
      nomad_datacenter = local.nomad_datacenter
      acl_enabled      = var.nomad_acl_enable
    })

    client_hcl = templatefile("${path.module}/templates/client.hcl.tftpl", {
      aws_region               = local.aws_region
      join_tag_key             = "nomad_ec2_join"
      join_tag_value           = var.nomad_join_tag_value
      node_pool                = var.node_pool
      drain_deadline           = var.drain_deadline
      gc_interval              = var.nomad_gc_interval
      gc_disk_usage_threshold  = var.nomad_gc_disk_usage_threshold
      gc_inode_usage_threshold = var.nomad_gc_inode_usage_threshold
      gc_max_allocs            = var.nomad_gc_max_allocs
      gc_parallel_destroys     = var.nomad_gc_parallel_destroys
      meta                     = local.node_meta
      host_volumes             = var.nomad_client_exec_host_volumes
      docker_enabled           = var.enable_docker_plugin
    })

    tls_hcl = templatefile("${path.module}/templates/tls.hcl.tftpl", {
      tls_http_enable = var.tls_http_enable
      tls_rpc_enable  = var.tls_rpc_enable
    })
  })

  instance_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadClusterSecrets"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.secrets_ssm_prefix}/*"
      },
      {
        Sid      = "DecryptClusterSecrets"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = coalesce(var.kms_key_arn, "*")
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${local.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid      = "DiscoverClusterPeers"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
        Resource = "*"
      },
    ]
  })
}
