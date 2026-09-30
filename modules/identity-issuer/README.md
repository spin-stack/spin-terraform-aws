# modules/identity-issuer

The installation's identity issuer, `https://id.<domain>`: where a system outside spin reads the
discovery document and the key set that verify a workspace's identity token. Its own origin -
CloudFront over a private bucket - so nothing of the installation serves the key set that decides
which tokens are its own.

What it publishes is what you commit. The key is `modules/controlplane`'s KMS key, which the
control plane signs with and never holds; its `identity_documents` output
(`module.spin.controlplane.identity_documents`) is the command that writes the documents from the
key's public half:

```sh
spin-controlplane identity documents --kms-key <arn> --domain <domain> --out identity/
```

Commit `identity/`, and point `documents` at it. A changed key set is then a change somebody
reviews, and no machine of the installation can write it.

Beside the key set is `.well-known/allowed_signers`: the same key as git verifies with, for a
commit a workspace signed. Anybody can check one:

```sh
curl -fsS https://id.<domain>/.well-known/allowed_signers > allowed_signers
git -c gpg.ssh.allowedSignersFile=allowed_signers verify-commit <commit>
```

CloudFront takes a certificate only from us-east-1, so the module is given a provider for it:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "identity_issuer" {
  source    = "github.com/spin-stack/spin-terraform-aws//modules/identity-issuer?ref=<tag>"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }

  name      = module.spin.controlplane.name
  domain    = module.spin.controlplane.domain
  zone_id   = module.spin.controlplane.public_zone_id
  documents = "${path.module}/identity"
}
```

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
| [aws_acm_certificate.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudfront_distribution.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_route53_record.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_object.document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.issuer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| documents | The directory `spin-controlplane identity documents --out` wrote: it holds .well-known/openid-configuration, .well-known/jwks.json and .well-known/allowed\_signers. | `string` | n/a | yes |
| domain | The installation's domain: the issuer is id.<domain>. | `string` | n/a | yes |
| name | The installation's name, as modules/controlplane's name output says it. | `string` | n/a | yes |
| zone\_id | The domain's public zone (modules/controlplane's public\_zone\_id). | `string` | n/a | yes |
| tags | Tags every resource carries. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| issuer | The issuer a workspace's identity token names, which a relying party is configured with. |
<!-- END_TF_DOCS -->
