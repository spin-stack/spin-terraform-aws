# modules/controlplane

The VPC, the buckets, the database's archive, the control plane's machine, the proxy's on its own,
the installation's CA and secrets, and the document each machine starts on. The repository's
[README](../../README.md) is how an installation is made with it and why it is shaped this way.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |
| random | ~> 3.7 |
| tls | ~> 4.1 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |
| tls | ~> 4.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_group.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_cloudwatch_log_group.boot](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_eip.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_instance_profile.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_instance_profile.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.session_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.runner_scope](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.runner_scope](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.controlplane_boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.controlplane_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.proxy_boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.proxy_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_key.identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_launch_template.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_route.internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_record.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_resolver_query_log_config.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_query_log_config) | resource |
| [aws_route53_resolver_query_log_config_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_query_log_config_association) | resource |
| [aws_route53_zone.internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53_zone.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.edge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.claim](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.controlplane_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.encryption_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.installation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.proxy_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.runner_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_subnet.edge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.proxy_to_collector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.proxy_to_controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.proxy_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.collector_from_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.controlplane_from_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.proxy_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.proxy_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.proxy_https_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [tls_private_key.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [aws_ami.spin_os](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ec2_instance_type.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_ec2_instance_type.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_iam_policy_document.boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.certificates](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controlplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.database_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.logs_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner_scope](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner_scope_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.session_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain | The base domain: the dashboard is app.<domain>, workspaces are *.ws.<domain>. | `string` | n/a | yes |
| spin\_version | The release the installation runs, as v<YYYYMMDD>.<N>: every machine boots the Spin OS image of it (spin-stack/ami), published into this account and tagged spin:version. | `string` | n/a | yes |
| acme\_email | The address Let's Encrypt writes to; empty is admin@<domain>. | `string` | `""` | no |
| admin\_email | Who the first administrator signs in as; empty is admin@<domain>. The one-time password is in the admin\_password\_parameter output's parameter. | `string` | `""` | no |
| availability\_zones | How many zones to make subnets in. The control plane, the proxy and the runners may each be started in any of them, which is what gives a group somewhere to go when a zone runs out. | `number` | `3` | no |
| collector | The collector: how often metrics are pushed to it. Which Alloy it is, is the image's. | ```object({ metric_interval = optional(string, "60s") })``` | `{}` | no |
| database\_lock\_days | The database archive's default Object Lock retention, in GOVERNANCE mode: how long what a delete or an overwrite left there can still be restored. The lifecycle removes it a day after (database\_bucket.tf). | `number` | `14` | no |
| decommission | Set to true, and applied, before destroying the installation: its buckets lose the policies that refuse every object write from outside the VPC - the destroy runs from outside it - and a destroy empties every bucket, data included, lifting legal holds and bypassing the GOVERNANCE retention. Never set on an installation that is to keep its data. | `bool` | `false` | no |
| dns\_query\_logs | Keep the VPC resolver's query log in CloudWatch: every name looked up, a workspace's included. It is Route 53 Resolver's, and off unless asked for. Each installation that turns it on takes one of the ten CloudWatch Logs resource policies a region of an account may have. | `bool` | `false` | no |
| flow\_logs | Keep the VPC's flow log in CloudWatch: every connection a security group accepted or refused. At a few hosts it is cents a month; a fleet whose workspaces move a lot of data pays about $0.50 a GB of flow records. | `bool` | `true` | no |
| identity\_record\_days | How many days the record of each identity token given is kept (identity/issued/ in the volumes bucket), which the key's signatures in CloudTrail are held to: longer than the bucket's lock, and long enough to answer who took an identity when. | `number` | `400` | no |
| image\_id | A Spin OS AMI for every machine, instead of the one images.json names for spin\_version in this region: a build of your own. It must carry that release: a machine refuses a document of another. | `string` | `""` | no |
| installation\_config | The installation's config file (spin's configs/spin-example.yaml), as YAML. This module adds what it knows - the domain, who joins as a host, the autoscaling settings below - and writes it where the control plane reads it at every start, which seeds the database from it before it serves. What the file later says differently is shown in the dashboard to apply or dismiss, and nothing is written over what an administrator decided. | `string` | `""` | no |
| instance\_type | The control plane's machine: the control plane, its database (PostgreSQL), the collector, and the stores of logs, traces and metrics it runs. | `string` | `"t8i.medium"` | no |
| internal\_zone | The private zone the components reach each other by: cp.<this> and proxy.<this>, resolved only inside the VPC. | `string` | `"spin.internal"` | no |
| log\_retention\_days | How long the flow and query logs are kept. | `number` | `30` | no |
| name | The installation's name, one per region of an account: every resource's prefix, the SSM path (/spin/<name>/...) each machine's document is at, and - with the region - every IAM name. Two installations of one account may share a name in two regions, and not in one (claim.tf). | `string` | `"spin"` | no |
| object\_lock\_days | The bucket's default Object Lock retention, in GOVERNANCE mode. A deleted object's bytes last this long, and the bucket's lifecycle (bucket.tf) removes them a day after. | `number` | `30` | no |
| proxy\_allowed\_cidrs | Where users may reach the proxy on 443 from: the dashboard, workspaces and SSH. Anywhere by default; an office's or a VPN's ranges close the installation to everyone else. The runners reach it from inside the VPC whatever this says, and 80 stays open for the ACME challenge. | `list(string)` | ```[ "0.0.0.0/0" ]``` | no |
| proxy\_instance\_type | The proxy's machine: Caddy and nothing else, the one address the internet reaches. | `string` | `"t8i.micro"` | no |
| quiet\_hours | HH:MM-HH:MM in time\_zone when an idle fleet is emptied at once rather than after runner\_idle\_minutes. A workspace asked for then still brings a runner up. Empty is none. | `string` | `""` | no |
| root\_volume\_gb | The control plane's disk: beside the read-only OS, /var takes the rest - the database, the logs' and metrics' stores and their caches. A new size is a new machine, replaced beside the old. | `number` | `40` | no |
| runner\_idle\_minutes | How long the fleet has no workspace running, starting or waiting before the runners' group is emptied. | `number` | `60` | no |
| runner\_policy | The host policy a runner starts with when it joins: how long it stays up once told to stop - a little less than the two minutes a spot reclaim gives - and the cloud that announces a reclaim. | ```object({ shutdown_grace = optional(string, "100s") preemption_source = optional(string, "aws") })``` | `{}` | no |
| tags | Tags on everything this module creates. | `map(string)` | `{}` | no |
| time\_zone | The IANA zone quiet\_hours are in. | `string` | `"UTC"` | no |
| vpc\_cidr | The VPC's range, a /16. One /20 public subnet per availability zone is carved from its first half, and one /24 for the proxy per zone from x.x.136.0 on. | `string` | `"10.42.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_email | Who the first administrator signs in as. |
| admin\_password\_parameter | The SSM SecureString holding the first administrator's one-time password: aws ssm get-parameter --with-decryption --name <this>. The first sign-in asks for a new one. |
| boot\_log\_group | The CloudWatch log group every machine's boot writes to, a stream per <role>/<step>/<instance-id>: a role's machines are one stream prefix. |
| boot\_log\_policy\_arn | Writing a machine's boot to that group, and nothing else: the runners module attaches it to the runners' role. |
| boundary\_arn | The permissions boundary every role of the installation carries; the runners module puts it on the runners' role. |
| bucket | The volumes' bucket: every workspace's disk, versioned under Object Lock, reached only through the VPC's endpoint. |
| ca\_cert | The installation's CA certificate, which every component trusts the control plane by. |
| collector | Where every process of the installation pushes its telemetry, host:port. Where the collector sends it is set in the dashboard. |
| controlplane\_group | The control plane's group of one. `aws autoscaling start-instance-refresh --auto-scaling-group-name <this>` replaces its machine beside itself; its machine is reached with `aws ssm start-session`, as the proxy's is. |
| database\_bucket | The database's archive: the base backups and WAL the control plane ships as it writes, and restores from when its machine is replaced. Its role alone reaches it. |
| domain | The base domain; the runners' relay is tunnel.app.<domain>, dialled at relay\_dial. |
| iam\_name | What the installation's IAM names begin with: its name and its region, since IAM is the account's and two regions may each have an installation of one name. The runners' role and instance profile are named for it. |
| identity\_documents | The commands that write the identity issuer's documents - discovery, key set, allowed signers and SPIFFE bundle - for modules/identity-issuer to publish: the X.509 CA the control plane made and keeps in its bucket, then the documents from it and the key's public half. Run them with credentials that may read both, and commit what they write. |
| identity\_key\_arn | The KMS key the control plane signs its workspaces' identity tokens with. |
| image | The Spin OS image of the installation's release, which the runners boot too: its id and its root device. |
| internal\_zone\_id | The private zone the components reach each other by, cp.<internal\_zone> and proxy.<internal\_zone>. |
| name | The installation's name, claimed in its region (claim.tf), which the runners' group and security group are named for. |
| name\_servers | The domain's public zone's nameservers, which its registrar points at. |
| proxy\_group | The proxy's group of one. Its machine, for `aws ssm start-session --target` (it has no SSH): aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <this> --query 'AutoScalingGroups[0].Instances[0].InstanceId'. |
| proxy\_ip | The proxy's elastic IP, where app.<domain>, tunnel.app.<domain> and *.ws.<domain> point: the one address of the installation the internet reaches. |
| public\_zone\_id | The domain's public zone, where modules/identity-issuer puts id.<domain>. |
| region | The region everything here is in, read from the provider rather than asked for. |
| relay\_dial | Where a runner dials the relay, host:port: the proxy inside the VPC, by the name the proxy of the moment points at itself. |
| runner\_config\_parameter\_arn | The runners' document, which the runners' role reads and nothing else of SSM. |
| runner\_idle\_minutes | How long the fleet is idle before the runners' group is emptied, which is why a first workspace waits for a machine's boot. |
| runner\_user\_data | A runner's user data: its role and the runners' document, as the systemd credentials Spin OS's spin-boot takes. |
| security\_group\_id | The control plane's group; the runners module opens 8080 on it to its own. |
| session\_manager\_policy\_arn | Session Manager into a machine, and nothing else of SSM: what the runners' role is given in place of AmazonSSMManagedInstanceCore, which reads every parameter. |
| standard\_vcpus | The on-demand standard vCPUs the control plane's and the proxy's machines take at most: two of each while an update replaces one. The runners module counts them against the quota on-demand runners share. |
| subnet\_ids | One public subnet per zone, for the runners' group. |
| url | The control plane as runners reach it, the address its certificate names. |
| vpc\_id | The VPC the runners go in. |
<!-- END_TF_DOCS -->
