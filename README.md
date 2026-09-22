# spin on AWS

A [spin](https://github.com/spin-stack/spin) installation on AWS, as one module:

```hcl
module "spin" {
  source       = "github.com/spin-stack/spin-terraform-aws?ref=<tag>"
  spin_version = "v20260921.02"
  domain       = "example.com"
}
```

The root composes two modules, and each can be used on its own
(`github.com/spin-stack/spin-terraform-aws//modules/controlplane?ref=<tag>`) where the root does
not expose what an installation needs to decide:

- **`modules/controlplane`** - the VPC, the bucket, the catalog on RDS, the control plane's
  machine, the proxy's on its own, and where runners find what they join with.
  `spin-install control-plane` and `spin-install proxy` do the installing; this module gives
  them machines, roles and a bucket that already satisfy them.
- **`modules/runners`** - an autoscaling group of runners that join by themselves, spot by
  default, that the control plane sizes: none until a workspace waits for a host, and none again
  once nothing has run for `runner_idle_minutes` (at once in the `quiet_hours`). It takes the
  control plane module's outputs whole, its name among them.

A variable of the root left unset is the module's own default: each defaults to null, which
the modules read as their default, so a default is said once. `examples/complete` is an
installation, and what `task lint` validates the modules through.

```bash
cd examples/complete
tofu init
tofu apply -var spin_version=v20260921.02 -var domain=example.com -var zone=Z0123456789
aws ssm start-session --target "$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(tofu output -raw controlplane_group)" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
sudo spin-controlplane bootstrap-password   # then https://app.<domain>
```

## What it decides, and why

- **No NAT gateway, no interface endpoints.** Every machine has a public address in a public
  subnet, and the bucket is reached through the S3 gateway endpoint, which is free. A NAT is
  $32 a month and a charge per GB before a workspace runs; an interface endpoint is $7 a
  month per zone each. A public address is not an open door: each machine's security group is
  what the internet may reach of it, and for all but one of them that is nothing.
- **The proxy is the only machine the internet reaches**, on 80 and 443, and it holds nothing
  but its own certificates and the CA it trusts the control plane by. The control plane has no
  rule for the internet at all - its public address is a way out - and its 8080 answers the
  proxy and the runners alone; the proxy may reach the control plane on 8080 and the web on
  80 and 443, and nothing else. A runner has no ingress. None of them has SSH: Session Manager
  is the way in, and IMDSv2 is required everywhere.
- **Inside the VPC the components are names.** A private zone, `internal_zone`
  (`spin.internal`, $0.50 a month), holds `cp.` and `proxy.` with a ten-second TTL, each
  written by the machine it names: the control plane's certificate carries `cp.spin.internal`,
  and the proxy, the runners and the collector's clients dial it, so a machine replaced is a
  record changed rather than an address in every runner's configuration. The runners reach the
  relay at `proxy.spin.internal` too (`spin-install runner --relay-dial`), checking its
  certificate as `tunnel.app.<domain>`, so the relay never leaves the VPC and the proxy's 443
  need not be open to wherever runners happen to be: `proxy_allowed_cidrs` can be the users'
  networks alone (80 stays open for the ACME challenge). `route53_zone_id` only writes the
  public records where the installation keeps its DNS there, and with it elsewhere they are the
  operator's, pointed at the `proxy_ip` output.
- **An update is a machine beside the old one, not a stop.** The control plane and the proxy
  are each an autoscaling group of one, and a change to what a machine is - `spin_version`, the
  image, the size - is a new launch template the group's instance refresh rolls out at 100%
  healthy: the new machine starts before the old one is retired, and a launch hook holds the
  refresh until it says it serves, abandoning it - and keeping the old - if it never does. A new
  control plane points `cp.` at itself and starts, which takes the term: the old one,
  superseded, closes and stays down, and runners and the proxy reconnect within seconds while
  every workspace runs on. A control plane that stays down three minutes asks its group to
  replace its machine. A new proxy restores the certificates the last one had from their own
  bucket (versioned, no Object Lock), starts Caddy, points `proxy.` at itself and takes the
  elastic IP. What is lost is seconds of API and open connections, never a workspace. Canonical
  publishing a newer image is such a change too: an apply after it rolls both machines onto it.
- **The proxy has subnets of its own**, and the control plane takes a browser's address only
  from them (`--trusted-proxy`): a runner, elsewhere in the VPC, cannot pass as the proxy.
- **No role can make itself more.** Every role both modules create carries one permissions
  boundary: none may write IAM or pass a role, assume any role but the runner scope, touch the
  VPC's network or a security group, run commands on another machine through SSM, or lift the
  bucket's lock or the logs. A policy attached later, by mistake or from a machine that was
  taken, cannot grant past it.
- **The control plane's secrets are its role's alone.** Session Manager is given as a policy of
  this module's - the agent's registration and its channels - and not AWS's
  `AmazonSSMManagedInstanceCore`, which also reads every parameter in the account: the
  parameters are under the account's `aws/ssm` key, so on the proxy or a runner it opened the
  encryption key. The boundary backs this: no role but the control plane's reads the key or
  the collector's token, no role but it and the runners' reads the pool's token, and none but
  it writes a parameter.
- **A runner installs its control plane's release**, asked of the control plane as it boots
  (the version header on its runner download), not one this module is given: while an update
  replaces the control plane - or after one is abandoned - a runner of the new release would
  be refused by the old. A runner that joins the old one is updated with the fleet when the
  new one leads. `spin_version` is the control plane module's alone.
- **What crossed the network is kept.** The VPC's flow log goes to CloudWatch for
  `log_retention_days` (30); `flow_logs = false` turns it off. The resolver's query log is
  Route 53 Resolver's, and `dns_query_logs = true` asks for it.
- **Telemetry, to Grafana Cloud, where `grafana_cloud` is given.** Grafana Alloy on the
  control plane's machine is the one collector: the control plane, the proxy and every runner
  push OTLP to it on 4317, which only they may reach, and only it holds the token and reaches
  Grafana Cloud. The token is an access policy token with metrics:write, logs:write and
  traces:write, written by the operator into the `grafana_token_parameter` SecureString: never
  in Terraform's state or a machine's user data. Metrics are pushed every 60 seconds, a point a
  minute per series. Which traces and metrics leave is the dashboard's (Admin → Settings →
  Telemetry): every trace that failed anywhere, every one slower than a threshold, a percent of
  the rest, and the metrics dropped by name; Alloy reads it every thirty seconds and decides at
  the end of each trace. Logs below `log_severity` (WARN) do not leave. The dashboard shows one
  monitoring: set Admin → Settings → Monitoring to Grafana Cloud with the stack's address, and
  the sidebar links to it and each host and workspace links to its traces and logs in Explore.
- **Each promise is a test.** `tofu test` in each module plans it with no account and asserts
  the above - the ingress rules, IMDSv2, encryption, the bucket's lock and policy, the roles and
  their boundary - and `task lint` runs it with the format check and validation, in CI on every push.
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
- **The catalog is RDS, and the control plane's machine holds nothing it cannot get back.**
  PostgreSQL 18 on `db.t4g.micro` (`database`), in subnets of its own with no route out of the
  VPC, taking 5432 from the control plane's group alone, with a week of backups and deletion
  protection; beside it the control plane writes an hourly catalog backup into the bucket. No
  password of it is anywhere Terraform writes: the master's is RDS's, in Secrets Manager, read
  once by the first boot to make the role `spin`, which signs in with an IAM token the machine's
  role signs and owns the database. The encryption key that opens what the catalog seals is in
  SSM from the first start on - not Terraform's, and it outlives any destroy - so a replaced
  control plane reads it back and serves the same catalog.
- **Every machine runs what the release workflow signed.** Each downloads cosign by the SHA-256
  this module pins (`cosign`), then its tarball and that tarball's bundle, and unpacks nothing
  that is not signed by `release.yml` at the version's tag. Nothing is a container: each role
  is a binary under systemd, as its own user.
- **Small machines.** The control plane and the proxy are `t3.micro` by default: with the
  catalog on RDS, the control plane is the control plane alone (and Alloy, where there is a
  collector - `t3.small` there for a busy fleet). Two of them and the database are the whole
  standing cost when no runner is up.

Hosts outside the group are still added the ordinary way - a one-time token from Admin → Hosts
and `spin-install runner` - and are policed by the same control plane.
