# The key the installation signs its workspaces' identity tokens with (spin's
# internal/controlplane/identity). In KMS, so the control plane asks for each signature and never
# holds the key: a copy of its machine, its disk or its database signs nothing. What may sign with
# it is the control plane's role, and only digests, only ES256 (iam.tf).
#
# A new key is every relying party's trust in the old one gone: it is replaced only on purpose, and
# the published key set (modules/identity-issuer) is written from this key.
variable "identity_record_days" {
  description = "How many days the record of each identity token given is kept (identity/issued/ in the volumes bucket), which the key's signatures in CloudTrail are held to: longer than the bucket's lock, and long enough to answer who took an identity when."
  type        = number
  default     = 400
  validation {
    condition     = var.identity_record_days > var.object_lock_days
    error_message = "identity_record_days is longer than object_lock_days: the lock keeps a record at least that long anyway."
  }
}

resource "aws_kms_key" "identity" {
  description              = "${local.name}: signs its workspaces' identity tokens"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 30
  tags                     = local.tags
}
