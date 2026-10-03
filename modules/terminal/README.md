# modules/terminal

The installation's browser terminal, `https://term.<domain>`: the SSH client a person reaches a
workspace with from a browser. It is spin's own Go compiled to WebAssembly. It holds a session to
the workspace's launch claim with the anchors the release built in, and to an anchor the person
holds, and it logs in with a passkey. Its own origin - CloudFront over a private bucket - so
nothing of the installation serves the code that asks a person's passkey, and the bucket's policy
refuses a write by any role of the installation.

What it publishes is a spin release's signed `spin-term.tar.gz`, which `task term:fetch` checks
against the signature the release's workflow made at its tag before it unpacks it:

```sh
task term:fetch RELEASE=<tag> OUT=term
```

Point `files` at that directory and `release` at the tag: a plan refuses files of another release.
Fetch the release the installation runs, so the terminal admits its hosts.

CloudFront takes a certificate only from us-east-1, so the module is given a provider for it:

```hcl
module "terminal" {
  source    = "github.com/spin-stack/spin-terraform-aws//modules/terminal?ref=<tag>"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }

  name     = module.spin.controlplane.name
  iam_name = module.spin.controlplane.iam_name
  domain   = module.spin.controlplane.domain
  zone_id  = module.spin.controlplane.public_zone_id
  release  = "<tag>"
  files    = "${path.module}/term"
}
```

The page asks the dashboard's API with the person's own session, which the control plane takes from
this origin for the terminal's calls alone, and the relay takes its WebSocket. Its Content Security
Policy lets it reach those two and nothing else.

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
| aws.us\_east\_1 | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudfront_distribution.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_response_headers_policy.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_route53_record.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_object.file](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.terminal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain | The installation's domain: the terminal is term.<domain>, and asks app.<domain>. | `string` | n/a | yes |
| files | The directory `task term:fetch RELEASE=<release>` unpacked the release's verified spin-term.tar.gz into: index.html, term.wasm, wasm\_exec.js, assets/, and the RELEASE it is. | `string` | n/a | yes |
| iam\_name | The prefix of the installation's roles (modules/controlplane's iam\_name): every one is refused a write here. | `string` | n/a | yes |
| name | The installation's name, as modules/controlplane's name output says it. | `string` | n/a | yes |
| release | The spin release whose terminal is published, which `files` must be: the terminal holds a launch claim to the release window around it. | `string` | n/a | yes |
| zone\_id | The domain's public zone (modules/controlplane's public\_zone\_id). | `string` | n/a | yes |
| tags | Tags every resource carries. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| url | The browser terminal's origin, which the dashboard opens a workspace's terminal at. |
<!-- END_TF_DOCS -->
