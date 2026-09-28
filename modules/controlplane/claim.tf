# An installation's name is claimed in its region before anything is made under it. Two
# installations of one name in one region would share every regional name - the parameters, the
# log groups, the groups - and the second apply would fail halfway, on the first of them, with the
# rest of it made. The claim is a parameter only a create can make (SSM refuses a PutParameter over
# one that exists), and every name this module gives is read through it (local.name), so the first
# resource the second installation makes is the one that refuses it, and nothing else is made.
#
# Its value is the name, not a secret: insecure_value, so the names read through it are not hidden
# in every plan as a sensitive value would be.
resource "aws_ssm_parameter" "claim" {
  name           = "/spin/${var.name}/claim"
  description    = "The name ${var.name} is taken in this region by the installation whose state holds this parameter"
  type           = "String"
  insecure_value = var.name
  # The claim's own tags cannot be read through the claim.
  tags = merge({ "spin:installation" = var.name }, var.tags)
}
