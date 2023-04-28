<a href="https://zerodha.tech"><img src="https://zerodha.tech/static/images/github-badge.svg" align="right" /></a>

# Nomad Cluster Setup

Terraform modules to deploy a [HashiCorp Nomad]((https://www.nomadproject.io/)) cluster on AWS using an Auto Scaling Group (ASG). The modules are designed to provision Nomad servers and clients in ASG, making it easy to manage the infrastructure for Nomad cluster. Additionally, the repository includes Packer scripts to build a custom Amazon Machine Image (AMI) with Nomad pre-installed.

![Nomad architecture](./docs/architecture.png)

- [Nomad Cluster Setup](#nomad-cluster-setup)
  - [AMI](#ami)
  - [AWS Resources](#aws-resources)
    - [Auto Scaling Group (ASG)](#auto-scaling-group-asg)
    - [Security Group](#security-group)
    - [IAM Role](#iam-role)
    - [ALB](#alb)
  - [Nomad Server](#nomad-server)
    - [Example Usage](#example-usage)
    - [Inputs](#inputs)
    - [Outputs](#outputs)
  - [Nomad Client](#nomad-client)
    - [Example Usage](#example-usage-1)
    - [Inputs](#inputs-1)
    - [Outputs](#outputs-1)
  - [Contributors](#contributors)
  - [Contributing](#contributing)
  - [LICENSE](#license)

## AMI

The repository includes a [Packer file](./packer/ami.pkr.hcl), to build a custom Amazon Machine Image (AMI) with Nomad and `docker` pre-installed. This AMI is used by the Terraform modules when creating the ASG instances.

To build the AMI, run:

```bash
cd packer
make build
```

NOTE: `dry_run` mode is toggled as true by default. To build the AMI, set the `dry_run` variable in [`Makefile`](./packer/Makefile) to `false`.

## AWS Resources

The key resources provisioned by this module are:

1. Auto Scaling Group (ASG)
2. Security Group
3. IAM Role
4. Application Load Balancer (ALB) (optional)

### Auto Scaling Group (ASG)

The module deploys Nomad on top of an Auto Scaling Group (ASG). For optimal performance and fault tolerance, it is recommended to run the Nomad server ASG with 3 or 5 EC2 instances distributed across multiple Availability Zones. Each EC2 instance should utilize an AMI built using the provided Packer script.

### Security Group

Each EC2 instance within the ASG is assigned a Security Group that permits:

- All outbound requests
- All inbound ports specified in the [Nomad documentation](https://developer.hashicorp.com/nomad/docs/install/production/requirements#ports-used)

The common Security Group is attached to both client and server nodes, enabling the Nomad agent to communicate and discover other agents within the cluster. The Security Group ID is exposed as an output variable for adding additional rules as needed. Furthermore, you can provide your own list of security groups as a variable to the module.

### IAM Role

An IAM Role is attached to each EC2 instance within the ASG. This role is granted a minimal set of IAM permissions, allowing each instance to automatically discover other instances in the same ASG and form a cluster with them.

### ALB

An internal Application Load Balancer (ALB) is _optionally_ created for the Nomad servers. The ALB is configured to listen on port 80/443 and forward requests to the Nomad servers on port 4646. The ALB is exposed as an output variable for adding additional rules as needed.

## Nomad Server

The [setup_server](./modules/nomad-servers/scripts/setup_server.tftpl.sh) script included in this project configures and bootstraps Nomad server nodes in an AWS Auto Scaling group. The script performs the following steps:

- Configures the Nomad agent as a server on the EC2 instances and uses the `nomad_join_tag_value` tag to auto-join the cluster. Once all the server instances discover each other, they elect a leader.
- Bootstraps the Nomad ACL system with a pre-configured token on the first server.
  - It waits for the cluster leader to get elected before bootstrapping ACL.
  - The token must be passed as the `nomad_acl_bootstrap_token` variable.

### Example Usage

```hcl
module "nomad_servers" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup//nomad-servers?ref=main"

  cluster_name         = "demo-nomad"
  nomad_join_tag_value = "demo"
  instance_count       = 3
  ami                  = "ami-xyz"
  vpc                  = "vpc-xyz"
  subnets              = "subnet-xyz"
  create_alb           = true
  nomad_alb_hostname   = "nomad.example.internal"

  nomad_gossip_encrypt_key  = var.nomad_gossip_encrypt_key
  nomad_acl_bootstrap_token = var.nomad_acl_bootstrap_token
}
```

### Terraform Module Reference

Check out [nomad_servers](./modules/nomad-servers/README.mkdn) documentation for module reference.

## Nomad Client

The [setup_client](./modules/nomad-clients/scripts/setup_client.tftpl.sh) script included in this project configures Nomad client nodes in an AWS Auto Scaling group. The script performs the following steps:

- Configures the Nomad agent as a client on the EC2 instances and uses the `nomad_join_tag_value` tag to auto-join the cluster.
- Configures DNS resolution for the Nomad cluster inside `exec` driver.
- Prepares configurations for different task drivers.

### Example Usage

```hcl
module "nomad_client_kite_alerts" {
  source = "git::https://github.com/zerodha/nomad-cluster-setup//nomad-clients?ref=main"

  cluster_name              = "demo-nomad"
  nomad_join_tag_value      = "demo"
  client_name               = "example-app"
  enable_docker_plugin      = true
  ami                       = "ami-abc"
  instance_type             = "c6a.xlarge"
  instance_desired_count    = 10
  vpc                       = "vpc-xyz"
  subnets                   = "subnet-xyz"
  route_53_resolver_address = "10.0.0.2"
}
```

### Terraform Module Reference

Check out [nomad_clients](./modules/nomad-clients/README.mkdn) documentation for module reference.

## Contributors

- [Karan Sharma](https://github.com/mr-karan)
- [Chinmay Pai](https://github.com/thunderbottom)


## Contributing

Contributions to this repository are welcome. Please submit a pull request or open an issue to suggest improvements or report bugs.


## LICENSE

[LICENSE](./LICENSE)
