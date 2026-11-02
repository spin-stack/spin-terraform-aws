# modules/runners

An autoscaling group of runners that join by themselves, spot by default, that the control plane
sizes. It takes `modules/controlplane`'s outputs whole. The repository's
[README](../../README.md) is how an installation is made with it.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.controlplane_fleet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.runner_boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_servicequotas_service_quota.runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/servicequotas_service_quota) | resource |
| [aws_vpc_security_group_egress_rule.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.collector_from_runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.controlplane_from_runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.controlplane_fleet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_servicequotas_service_quota.runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/servicequotas_service_quota) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| controlplane | What this module needs of the control plane module's outputs, named one by one: its name, where the runners go, their document, what a runner's machine runs at its first boot, and what taking the runners' groups away is, which the security group and the launch template outlive. | ```object({ name = string iam_name = string vpc_id = string subnet_ids = list(string) security_group_id = string runner_document_arn = string runner_user_data = string images = map(object({ id = string, root_device = string })) boot_log_policy_arn = string standard_vcpus = number boundary_arn = string runner_groups = string })``` | n/a | yes |
| runners | The control plane module's runners output: what it decides of the runners - the launch template's name, which it makes each host class's group from, its role, what the template's machines need of an instance type, and what the quota is sized by. | ```object({ launch_template = string controlplane_role = string vcpus_max = number max_hosts = number spot = bool data_volume_gb = number nested_virtualization = bool })``` | n/a | yes |
| request\_quota | Ask AWS for the vCPU quota max\_hosts runners need, when the account's is lower (quota.tf). A request costs nothing and lowers nothing when it is removed. | `bool` | `true` | no |
| root\_volume\_gb | The runner's root disk: the OS and the machine's files; its data is on the instance store or data\_volume\_gb. | `number` | `30` | no |
| tags | Tags on everything this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| launch\_template | The runners' launch template, which every host class's group the control plane makes starts its machines from; its default version is the release's. |
| security\_group\_id | The runners' security group: nothing in, everything out - a workspace's egress is filtered on the host by spin. |
<!-- END_TF_DOCS -->
