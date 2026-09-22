# spin on AWS

Two modules, and `example/` composing them into an installation.

- **`controlplane/`** — the VPC, the bucket, the control plane's machine, the proxy's on its
  own, and where runners find what they join with. `spin-install control-plane` and
  `spin-install proxy` do the installing; this module gives them machines, roles and a bucket
  that already satisfy them.
- **`runners/`** — an autoscaling group of runners that join by themselves, spot by default,
  that the control plane sizes: none until a workspace waits for a host, and none again once
  nothing has run for `runner_idle_minutes` (at once in the `quiet_hours`).

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
  month per zone each. A public address is not an open door: each machine's security group is
  what the internet may reach of it, and for all but one of them that is nothing.
- **The proxy is the only machine the internet reaches**, on 80 and 443, and it holds nothing
  but its own certificates and the CA it trusts the control plane by. The control plane has no
  rule for the internet at all — its public address is a way out — and its 8080 answers the
  proxy and the runners alone; the proxy may reach the control plane on 8080 and the web on
  80 and 443, and nothing else. A runner has no ingress. None of them has SSH: Session Manager
  is the way in, and IMDSv2 is required everywhere.
- **Inside the VPC the proxy is its private address.** A private hosted zone answers
  `app.<domain>` and `*.app.<domain>` there, so a runner's relay never leaves the VPC and the
  proxy's 443 need not be open to wherever runners happen to be: `proxy_allowed_cidrs` can be
  the users' networks alone (80 stays open for the ACME challenge).
- **No role can make itself more.** Every role both modules create carries one permissions
  boundary: none may write IAM or pass a role, assume any role but the runner scope, touch the
  VPC's network or a security group, run commands on another machine through SSM, or lift the
  bucket's lock or the logs. A policy attached later, by mistake or from a machine that was
  taken, cannot grant past it.
- **What crossed the network is kept.** The VPC's flow log and the resolver's query log go to
  CloudWatch for `log_retention_days` (30); `network_logs = false` turns both off.
- **Each promise is a test.** `tofu test` in each module plans it with no account and asserts
  the above — the ingress rules, IMDSv2, encryption, the bucket's lock and policy, the roles and
  their boundary — and `task lint:terraform` runs it with the rest of `task lint`.
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
- **The control plane sizes the group, not a schedule or a metric.** It is the one that knows a
  workspace is waiting for a host, and that the last one stopped an hour ago. The first create
  or start of the day waits in *Waiting for a host* for the few minutes a runner takes to boot
  and install; the control plane has asked the group for one, and places the workspace on it
  when it registers. It only ever goes from none to one, adds one while a workspace has waited
  longer than a host takes to come, and goes back to none: it never picks one host of several
  to take away, since the group would choose which. Its role may resize that one group and
  nothing else, and the group's name, `<name>-runners`, is the contract between the modules.
  `installation_config` is the installation's config file, which this module applies with those
  settings added: it is then the file's one author.
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
