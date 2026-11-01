# Upgrading from v1 to v2

v2 is a major release. Existing clusters can stay on the `release/v1` branch,
which gets security and critical fixes only. Move a cluster to v2 by building
a new v2 cluster next to it, not by changing the module ref in place.

## Why a new cluster

v2 changes the boot process, where secrets live, the agent config layout and
the shape of stateful nodes. An in-place change touches every instance of a
running scheduler at once, and old stateful nodes keep their data on the root
disk, which v2 does not manage. A new cluster lets you move jobs one at a time,
compare behaviour, and keep the old cluster as the rollback until the end.

## Steps

1. Build the image. See [AMI](../README.md#ami). bootc and mutable images both
   work.
2. Put the secrets in SSM Parameter Store under a new prefix. See
   [Secrets](../README.md#secrets). Generate a new gossip key and bootstrap
   token; do not reuse the old cluster's.
3. Create the v2 cluster with a new `cluster_name`, Nomad region and
   `nomad_join_tag_value`, so its agents can never join the old cluster.
4. Recreate ACL policies, namespaces and auth methods on the new cluster.
5. Move stateless jobs: register them on the new cluster, shift traffic, stop
   them on the old one.
6. Move stateful jobs with their own replication. Add a static node (see
   below) on the new cluster, run the job there as a replica of the old one,
   let it catch up, then promote it and stop the old one. Postgres streaming
   replication, Redis replicas and Kafka or NATS cluster membership all work
   this way.
7. Once the old cluster runs nothing, destroy it.

## Input changes

| v1                                       | v2                                                     |
| ---------------------------------------- | ------------------------------------------------------ |
| `nomad_gossip_encrypt_key`, `nomad_acl_bootstrap_token`, `tls_certificates` | `secrets_ssm_prefix`; values read from SSM at boot |
| `enable_tls`                             | `tls_enabled`                                          |
| `default_iam_policies`                   | `iam_policy_arns`                                      |
| `aws_region`                             | Removed; taken from the AWS provider                   |
| `nomad_bootstrap_expect`                 | Removed; equals `instance_count`                       |
| `ssh_user`, `ssh_public_keys`            | Removed                                                |
| nomad-clients `vpc`                      | Removed                                                |
| `client_type = "ec2"`, `ec2_count`       | `static_nodes`, a map of named nodes with data volumes |
| raw_exec and privileged Docker always on | `enable_raw_exec`, `docker_allow_privileged`, both off |
| `nomad_ui_label` (string, rc only)       | `nomad_ui_label = { text, background_color, text_color }` |

The [CHANGELOG](../CHANGELOG.md) lists every change.

## Stateful nodes

`static_nodes` replaces the v1 `ec2` client type:

```hcl
module "nomad_clients_postgres" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup.git//modules/nomad-clients?ref=v2.0.0"
  # ...
  client_name = "postgres"
  static_nodes = {
    "pg-1" = { subnet_id = "subnet-aaa", data_volume_size = 500 }
    "pg-2" = { subnet_id = "subnet-bbb", data_volume_size = 500 }
  }
  data_volume_tags = { backup = "daily" }
}
```

Each node gets an EBS data volume in its subnet's AZ, mounted at
`/var/lib/nomad-data` before Nomad starts and exposed as the host volume
`data`. The node has meta `static_node = "pg-1"`, so a job can pin a group to
it:

```hcl
group "db" {
  constraint {
    attribute = "${meta.static_node}"
    value     = "pg-1"
  }

  volume "data" {
    type   = "host"
    source = "data"
  }
}
```

The data volume has `prevent_destroy`, and the instance has termination
protection. To move a node to a new AMI or config:

1. Set `static_termination_protection = false` and apply.
2. `tofu apply -replace='module.nomad_clients_postgres.aws_instance.static["pg-1"]'`.
   The old instance stops, the volume detaches, and the new instance mounts it.
3. Set `static_termination_protection = true` and apply.

To remove a node and delete its data, remove it from `static_nodes`, run
`tofu state rm` on its `aws_ebs_volume.data` entry, apply, then delete the
volume in AWS after taking a snapshot.
