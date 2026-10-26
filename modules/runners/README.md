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
| [aws_autoscaling_group.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.runner_boot_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_servicequotas_service_quota.runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/servicequotas_service_quota) | resource |
| [aws_vpc_security_group_egress_rule.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.collector_from_runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.controlplane_from_runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.ec2_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_servicequotas_service_quota.runners](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/servicequotas_service_quota) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| controlplane | The control plane module's outputs, as they are: its name, where the runners go, their document, and what a runner's machine runs at its first boot. | ```object({ name = string iam_name = string vpc_id = string subnet_ids = list(string) security_group_id = string runner_document_arn = string runner_user_data = string images = map(object({ id = string, root_device = string })) boot_log_policy_arn = string standard_vcpus = number boundary_arn = string })``` | n/a | yes |
| data\_volume\_gb | An EBS volume for the runner's data, for an instance type with no local NVMe. Zero uses the instance store, which is the right disk for volumes' cache and costs nothing more. A machine's boot takes an empty EBS volume where it has one, and the instance store otherwise. | `number` | `0` | no |
| drain\_seconds | How long a host the group is taking away is held while it empties itself: the termination hook's timeout. At least the pool token's --shutdown-grace; the hook is left to expire, so this is also how long each scale-in takes. | `number` | `150` | no |
| instance\_types | The types the group may start, as EC2's allowed\_instance\_types takes them: names, or patterns with * (c8id.*). The group starts any type they match that has vcpus and the disk data\_volume\_gb leaves the data on - a local NVMe while it is 0, so a d variant - and AWS adds the sizes and types it brings out without this list changing.  Keep them one CPU generation: a checkpoint records the processor and its flags as -cpu host showed them (MachineIdentity in spin's internal/runner/vmm), and resumes only onto a host that shows the same - a workspace suspended at night on one family and brought back on another cold-boots. Nested virtualization is offered on C8i, M8i, R8i (and their d variants), C7i, M7i, R7i and I7i. Not c8i* for c8i.*: that matches the flex types too.  For spot, the more pools a request can draw on the likelier a machine, and one type is one pool per zone. How the types these match score in a region, before installing:   aws ec2 get-spot-placement-scores --target-capacity 1 --region-names <region> \     --single-availability-zone --instance-requirements-with-metadata \     '{"ArchitectureTypes":["x86\_64"],"InstanceRequirements":{"VCpuCount":{"Min":32,"Max":48},"MemoryMiB":{"Min":65536},"LocalStorage":"required","AllowedInstanceTypes":[<the types>]}}' | `list(string)` | ```[ "c8i.*", "c8id.*", "m8i.*", "m8id.*", "r8i.*", "r8id.*" ]``` | no |
| max\_hosts | The most runners the group may have. How many it has is the control plane's to decide: none until a workspace waits for a host, and none again once nothing has run for the control plane module's runner\_idle\_minutes. | `number` | `1` | no |
| nested\_virtualization | Enable KVM inside the instance. False for .metal types, which have it by being metal and refuse the option. | `bool` | `true` | no |
| request\_quota | Ask AWS for the vCPU quota max\_hosts runners need, when the account's is lower (quota.tf). A request costs nothing and lowers nothing when it is removed. | `bool` | `true` | no |
| rollout | How a new release reaches the runners. idle: when the fleet next empties - no workspace running, starting or being saved - the next host boots it, and no workspace is moved for it; a host keeps the old release until then, which its control plane allows for 90 days. rolling: the hosts are replaced at once, one at a time, each old one's workspaces suspended to the bucket and resumed on the new one - for a fleet that never empties. | `string` | `"idle"` | no |
| root\_volume\_gb | The runner's root disk: the OS and the machine's files; its data is on the instance store or data\_volume\_gb. | `number` | `30` | no |
| spot | Every host a spot instance. The policy a runner joins under (the control plane module's runner\_policy) is what tells each one a stop is a reclaim. | `bool` | `true` | no |
| tags | Tags on everything this module creates. | `map(string)` | `{}` | no |
| vcpus | How many vCPUs a runner may have, at least and at most: each type instance\_types matches within it is a pool the group may draw on. max is also what the quota is sized by (quota.tf). | `object({ min = number, max = number })` | ```{ "max": 48, "min": 32 }``` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| autoscaling\_group | The runners' group, which the control plane sizes: empty until a workspace waits for a host. |
| security\_group\_id | The runners' security group: nothing in, everything out - a workspace's egress is filtered on the host by spin. |
<!-- END_TF_DOCS -->
