# spin on AWS

Two modules, and `example/` composing them into an installation.

- **`controlplane/`** — the VPC, the bucket, the control plane's machine with the proxy
  beside it, and where runners find what they join with. `spin-install control-plane
  --with-proxy` does the installing; this module gives it a machine, a role and a bucket that
  already satisfy it.
- **`runners/`** — an autoscaling group of runners that join by themselves, spot by default,
  optionally on a schedule.

```bash
cd example
tofu init
tofu apply -var spin_version=v20260921.02 -var domain=example.com -var zone=Z0123456789
aws ssm start-session --target "$(tofu output -raw controlplane_instance)"
sudo docker exec spin-controlplane controlplane bootstrap-password   # then https://app.<domain>
```

## What it decides, and why

- **No NAT gateway, no interface endpoints.** Every machine has a public address in a public
  subnet, and the bucket is reached through the S3 gateway endpoint, which is free. A NAT is
  $32 a month and a charge per GB before a workspace runs; an interface endpoint is $7 a
  month per zone each. Nothing listens on a runner, so its public address reaches nothing, and
  its security group has no ingress at all.
- **The bucket answers object requests only through that endpoint.** A runner's credential is
  minted by the control plane for an hour and scoped to its volumes; copied off the machine,
  it opens nothing. Bucket-level calls stay open to the account, so this module can still be
  applied from outside the VPC.
- **The control plane's role cannot lift the lock.** It may not bypass a retention, rewrite
  the bucket's policy or change its Object Lock rule. Spin writes the bucket's lifecycle rules
  itself, so this module declares none.
- **Runners join with a pool's token.** The control plane mints one every `pool_token_rotation`
  (`controlplane registration-token --reusable`, in the bootstrap administrator's name and on
  the audit) into an SSM SecureString that only it and the runners' role read, with the CA
  beside it. The
  token carries the host policy each runner starts with: by default, a spot reclaim announced
  by AWS and 100 seconds to empty itself.
- **A scale-in is a drain.** The group's termination hook holds a host for `drain_seconds`; the
  runner reads the lifecycle state from the metadata service and suspends its workspaces to
  the bucket, where they resume on the next host. A spot reclaim is the same with a two-minute
  notice, and capacity rebalancing starts the replacement first.
- **The control plane's data outlives its machine.** `/etc/spin-stack` and `/var/lib/spin-stack`
  are on their own volume, snapshotted daily, and the encryption key is copied to SSM on the
  first start. The volume has `prevent_destroy`, so `tofu destroy` refuses until that line is
  removed; the key's parameter is not Terraform's at all, and outlives any destroy.

Hosts outside the group are still added the ordinary way — a one-time token from Admin → Hosts
and `spin-install runner` — and are policed by the same control plane.
