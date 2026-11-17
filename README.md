# The Spin OS image catalog

What an installation's Terraform provider ([spin-stack/terraform-provider-spin](https://github.com/spin-stack/terraform-provider-spin))
reads a spin release's images from:

- `releases/<release>.json`: each role's builds by revision - the PCRs an instance measures, the
  statement of them its release signed with the bundle that signs it, the disk's provenance, and the
  image in each region - and the signed revocations of some of them.
- `channels/<channel>.json`: the signed statement of the release a channel names (`edge`, `stable`).

spin-stack/ami's release, revoke and promote workflows write it, with no pull request. Nothing here
is believed for where it is: the provider believes a build only when ami's release workflow signed
its statement and the statement says its PCRs, and a revocation or a channel only as statements
signed by ami's workflows (go-tools' `catalog`). A change to this branch that no workflow signed
opens nothing; it fails the plan of every installation that reads it.

The releases from before the catalog were imported from the module's `images.json` and
`measurements.json` (`spin-os images catalog import`), each verified under its release's signature.
