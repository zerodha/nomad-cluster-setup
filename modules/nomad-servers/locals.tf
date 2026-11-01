locals {
  aws_region       = data.aws_region.current.region
  nomad_datacenter = coalesce(var.nomad_datacenter, var.cluster_name)

  setup_server = templatefile("${path.module}/scripts/setup_server.tftpl.sh", {
    aws_region              = local.aws_region
    cluster_name            = var.cluster_name
    secrets_ssm_prefix      = var.secrets_ssm_prefix
    acl_enabled             = var.nomad_acl_enable
    tls_enabled             = var.tls_enabled
    tls_http_enable         = var.tls_http_enable
    nomad_region            = var.nomad_region
    nomad_file_limit        = var.nomad_file_limit
    raft_backup_bucket      = var.nomad_raft_backup_bucket
    raft_backup_on_calendar = var.nomad_raft_backup_on_calendar
    extra_config            = var.nomad_extra_config

    base_hcl = templatefile("${path.module}/templates/base.hcl.tftpl", {
      nomad_region     = var.nomad_region
      nomad_datacenter = local.nomad_datacenter
      acl_enabled      = var.nomad_acl_enable
    })

    server_hcl = templatefile("${path.module}/templates/server.hcl.tftpl", {
      aws_region                      = local.aws_region
      bootstrap_expect                = var.instance_count
      join_tag_key                    = "nomad_ec2_join"
      join_tag_value                  = var.nomad_join_tag_value
      job_gc_threshold                = var.nomad_job_gc_threshold
      eval_gc_threshold               = var.nomad_eval_gc_threshold
      batch_eval_gc_threshold         = var.nomad_batch_eval_gc_threshold
      deployment_gc_threshold         = var.nomad_deployment_gc_threshold
      ui_label                        = var.nomad_ui_label
      http_max_conns_per_client       = var.nomad_http_max_conns_per_client
      memory_oversubscription_enabled = var.nomad_enable_mem_oversubscription
    })

    tls_hcl = templatefile("${path.module}/templates/tls.hcl.tftpl", {
      tls_http_enable = var.tls_http_enable
      tls_rpc_enable  = var.tls_rpc_enable
    })
  })

  instance_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
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
      ], var.nomad_raft_backup_bucket == "" ? [] : [
      {
        Sid      = "WriteRaftSnapshots"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.nomad_raft_backup_bucket}/${var.cluster_name}/*"
      },
    ])
  })
}
