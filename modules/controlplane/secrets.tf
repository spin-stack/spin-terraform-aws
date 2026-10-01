# The installation's secrets, made here and written to SSM by this apply and by nothing else: no
# machine of the installation can write a parameter (boundary.tf), so what a machine reads is
# what this module wrote, and a machine that was taken cannot leave something for the next one.
#
# The encryption key is not one of them: no apply makes it, and nothing stores it
# (attested_key.tf).
#
# The first administrator's password never reaches the state: an ephemeral value written through a
# write-only attribute, once - value_wo_version is what says when, and it does not change on its
# own. The CA is in the state on purpose:
# its certificate is what every runner and the proxy are given in their documents, so this
# module has to know it, and a certificate whose key the state does not hold is one the next
# apply would make again. The state is encrypted for that reason (the deployment's
# encryption block), and the key is in SSM for the control plane alone.

locals {
  ca_parameter             = "/spin/${local.name}/controlplane-ca"
  admin_password_parameter = "/spin/${local.name}/bootstrap-password"
  admin_email              = var.admin_email != "" ? var.admin_email : "admin@${var.domain}"
}

# The certificate authority every component trusts the control plane by. Ten years and no early
# renewal: a new CA is every runner and the proxy distrusting the control plane until each is
# replaced, and nothing should do that as a side effect of an apply.
resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
  lifecycle {
    prevent_destroy = true
  }
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  subject {
    common_name  = "${local.name} spin CA"
    organization = "spin"
  }
  is_ca_certificate     = true
  validity_period_hours = 87600
  allowed_uses          = ["cert_signing", "crl_signing"]
  lifecycle {
    prevent_destroy = true
  }
}

# Certificate and key, which only the control plane reads (tls.ca_at): it issues its own
# certificate under it at every start. The runners and the proxy are given the certificate alone,
# in their documents.
resource "aws_ssm_parameter" "ca" {
  name        = local.ca_parameter
  description = "The CA of ${local.name}: its certificate and key, for the control plane alone"
  type        = "SecureString"
  value       = "${tls_self_signed_cert.ca.cert_pem}${tls_private_key.ca.private_key_pem}"
  tags        = local.tags
}

# The first administrator's one-time password, where the operator reads it:
#   aws ssm get-parameter --with-decryption --name <admin_password_parameter>
# The first sign-in asks for a new one, and this one opens nothing after that.
ephemeral "random_password" "admin" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "admin_password" {
  name             = local.admin_password_parameter
  description      = "The one-time password of ${local.admin_email}, the first administrator of ${local.name}"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.admin.result
  value_wo_version = 1
  tags             = local.tags
}
