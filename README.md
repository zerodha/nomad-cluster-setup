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

### Inputs

| Name                      | Description                                                         | Type         | Default                                                      | Required |
| ------------------------- | ------------------------------------------------------------------- | ------------ | ------------------------------------------------------------ | :------: |
| alb_certificate_arn       | ARN of the HTTPS certificate to use with the ALB                    | string       | ""                                                           |    no    |
| ami                       | AMI ID to use for deploying Nomad servers                           | string       | n/a                                                          |   yes    |
| autoscale_metrics         | List of autoscaling metrics to enable for the Autoscaling Group     | list(string) | _(see [variables.tf](./modules/nomad-servers/variables.tf))_ |    no    |
| aws_region                | AWS region to deploy the Nomad cluster in                           | string       | "ap-south-1"                                                 |    no    |
| cluster_name              | Identifier for the cluster, used as a prefix for all resources      | string       | n/a                                                          |   yes    |
| cluster_tags              | Map of tag key-value pairs to assign to the EC2 instances           | map(string)  | n/a                                                          |   yes    |
| create_alb                | Whether to create an ALB for the Nomad servers or not               | bool         | false                                                        |    no    |
| default_iam_policies      | List of IAM policy ARNs to attach to the Nomad server instances     | list(string) | []                                                           |    no    |
| default_security_groups   | List of security group IDs to assign to the Nomad server instances  | list(string) | []                                                           |    no    |
| ebs_tags                  | A map of additional tags to apply to the EBS volumes                | map(string)  | {}                                                           |    no    |
| instance_count            | Number of Nomad server instances to run                             | number       | 3                                                            |    no    |
| instance_type             | Instance type to use for the Nomad server instances                 | string       | "c5a.large"                                                  |    no    |
| iam_tags                  | A map of custom tags to be assigned to the IAM role                 | map(string)  | {}                                                           |    no    |
| nomad_acl_bootstrap_token | Nomad ACL bootstrap token to use for bootstrapping ACLs             | string       | n/a                                                          |   yes    |
| nomad_alb_hostname        | ALB hostname to use for accessing the Nomad web UI                  | string       | "nomad.example.internal"                                     |    no    |
| nomad_bootstrap_expect    | Number of instances expected to bootstrap a new Nomad cluster       | number       | 3                                                            |    no    |
| nomad_gossip_encrypt_key  | Gossip encryption key to use for Nomad servers                      | string       | n/a                                                          |   yes    |
| nomad_join_tag_value      | Value of the tag used for Nomad server auto-join                    | string       | n/a                                                          |   yes    |
| nomad_server_incoming_ips | List of IPs to allow incoming connections from to Nomad server ALBs | list(string) | []                                                           |    no    |
| subnets                   | List of subnets to assign for deploying instances                   | list(string) | []                                                           |    no    |
| vpc                       | ID of the AWS VPC to deploy all the resources in                    | string       | n/a                                                          |   yes    |


### Outputs

| Name                            | Description                                     |
| ------------------------------- | ----------------------------------------------- |
| alb_dns_name                    | The DNS name of the ALB                         |
| alb_security_group_id           | The ID of the ALB security group                |
| nomad_server_asg_name           | The name of the Nomad server Auto Scaling Group |
| nomad_server_asg_arn            | The ARN of the Nomad server Auto Scaling Group  |
| nomad_server_launch_template_id | The ID of the Nomad server launch template      |
| nomad_agent_security_group_id   | The ID of the Nomad agent security group        |
| nomad_server_iam_role_arn       | The ARN of the Nomad server IAM role            |


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


### Inputs


| Name                      | Description                                                                   | Type         | Default                                                      | Required |
| ------------------------- | ----------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------ | :------: |
| ami                       | Amazon Machine Image (AMI) ID used for deploying Nomad clients                | string       | n/a                                                          |   yes    |
| autoscale_metrics         | List of autoscaling metrics to monitor for Auto Scaling Group (ASG) instances | list(string) | _(see [variables.tf](./modules/nomad-clients/variables.tf))_ |    no    |
| client_name               | Name of the Auto Scaling Group (ASG) nodes deployed as Nomad clients          | string       | n/a                                                          |   yes    |
| client_security_groups    | List of security groups to attach to the Nomad client nodes                   | list(string) | []                                                           |    no    |
| client_type               | Type of client to deploy: 'ec2' or 'asg'                                      | string       | "asg"                                                        |    no    |
| cluster_name              | Identifier used for naming all resources associated with the cluster          | string       | n/a                                                          |   yes    |
| cluster_tags              | Key-value pairs of tags to assign to the EC2 instances spawned by the ASG     | map(string)  | {}                                                           |    no    |
| create_alb                | Whether to create an Application Load Balancer (ALB) or not                   | bool         | false                                                        |    no    |
| default_iam_policies      | List of IAM policies to assign to the Nomad clients                           | list(string) | []                                                           |    no    |
| ebs_volume_size           | The size of the EBS volume in gigabytes                                       | number       | 100                                                          |    no    |
| ebs_tags                  | A map of custom tags to be assigned to the EBS volumes                        | map(string)  | {}                                                           |    no    |
| ec2_count                 | Number of Nomad client EC2 instances to run                                   | number       | 1                                                            |    no    |
| enable_docker_plugin      | Whether to enable the Docker plugin on the client nodes                       | bool         | true                                                         |    no    |
| healthcheck_type          | Health check type for the ASG, either 'EC2' or 'ELB'                          | string       | "EC2"                                                        |    no    |
| iam_instance_profile      | Name of the existing IAM Instance Profile to use                              | string       | ""                                                           |    no    |
| iam_tags                  | A map of custom tags to be assigned to the IAM role                           | map(string)  | {}                                                           |    no    |
| instance_desired_count    | Desired number of Nomad clients to run                                        | number       | 1                                                            |    no    |
| instance_max_count        | Maximum number of Nomad clients to run                                        | number       | 3                                                            |    no    |
| instance_min_count        | Minimum number of Nomad clients to run                                        | number       | 0                                                            |    no    |
| instance_type             | Instance type to use for the Nomad clients                                    | string       | "c5a.large"                                                  |    no    |
| nomad_join_tag_value      | The value of the tag used for Nomad server auto-join                          | string       | n/a                                                          |   yes    |
| override_instance_types   | List of instance types to define in the mixed_instances_policy block          | list(string) | []                                                           |    no    |
| route_53_resolver_address | Route53 resolver address for querying DNS inside exec tasks                   | string       | n/a                                                          |   yes    |
| subnets                   | List of subnets to assign for deploying instances                             | list(string) | []                                                           |    no    |
| target_group_arns         | List of target groups assigned in the ALB to connect to the ASG               | list(string) | []                                                           |    no    |
| vpc                       | AWS Virtual Private Cloud (VPC) to deploy all resources in                    | string       | n/a                                                          |   yes    |


### Outputs

| Name                            | Description                                          |
| ------------------------------- | ---------------------------------------------------- |
| nomad_client_iam_profile        | IAM Profile created for Nomad Client                 |
| nomad_client_asg                | Autoscaling group for the Nomad client nodes         |
| nomad_client_iam_role_arn       | ARN of the IAM role for the Nomad client nodes       |
| nomad_client_launch_template_id | ID of the launch template for the Nomad client nodes |

## Contributors

- [Karan Sharma](https://github.com/mr-karan)
- [Chinmay](https://github.com/thunderbottom)


## Contributing

Contributions to this repository are welcome. Please submit a pull request or open an issue to suggest improvements or report bugs.


## LICENSE

[LICENSE](./LICENSE)
