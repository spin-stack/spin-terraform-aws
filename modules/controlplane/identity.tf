# The key the installation signs its workspaces' identity tokens with (spin's
# internal/controlplane/identity). In KMS, so the control plane asks for each signature and never
# holds the key: a copy of its machine, its disk or its database signs nothing. What may sign with
# it is the control plane's role, and only digests, only ES256 (iam.tf).
#
# A new key is every relying party's trust in the old one gone: it is replaced only on purpose, and
# the published key set (modules/identity-issuer) is written from this key.
resource "aws_kms_key" "identity" {
  description              = "${local.name}: signs its workspaces' identity tokens"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 30
  tags                     = local.tags
}
