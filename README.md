# spin on AWS

A [spin](https://github.com/spin-stack/spin) installation on AWS, as one module:

```hcl
module "spin" {
  source           = "github.com/spin-stack/spin-terraform-aws?ref=<tag>"
  spin_version     = "v20260921.02"
  spin_boot_sha256 = "<from that release's checksums.txt>"
  domain           = "example.com"
}
```

The root composes two modules, and each can be used on its own
(`github.com/spin-stack/spin-terraform-aws//modules/controlplane?ref=<tag>`) where the root does
not expose what an installation needs to decide:

- **`modules/controlplane`** - the VPC, the bucket, the catalog on RDS, the control plane's
  machine, the proxy's on its own, the installation's CA and secrets, and the document each
  machine starts on.
- **`modules/runners`** - an autoscaling group of runners that join by themselves, spot by
  default, that the control plane sizes: none until a workspace waits for a host, and none again
  once nothing has run for `runner_idle_minutes` (at once in the `quiet_hours`). It takes the
  control plane module's outputs whole, its name among them.

A variable of the root left unset is the module's own default: each defaults to null, which
the modules read as their default, so a default is said once. `examples/complete` is an
installation, and what `task lint` validates the modules through.

## Before you start

- [OpenTofu](https://opentofu.org/docs/intro/install/) 1.11 or newer, the
  [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) signed
  in to the account (`aws sts get-caller-identity` answers), and the
  [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  for a shell on a machine.
- A domain whose DNS you can change. If it is a Route 53 zone in this account, its id is
  `aws route53 list-hosted-zones-by-name --dns-name <domain> --query 'HostedZones[0].Id'`.
- Room for runners: each is a spot `m8id.8xlarge` (32 vCPUs) by default, and a new account's spot
  vCPU quota may be lower (Service Quotas → EC2 → "All Standard Spot Instance Requests").
  `runner_spot = false` uses on-demand instead.

## Installing

Once per account and region, a bucket and a KMS key for OpenTofu's state (the state holds the
installation's CA key, so it is encrypted and never a file on your machine):

```bash
cd bootstrap
tofu init && tofu apply
```

Then the installation. `examples/complete` is one; copy it anywhere, or use it as it is:

```bash
cd ../examples/complete
cp terraform.tfvars.example terraform.tfvars    # and fill it in
$(tofu -chdir=../../bootstrap output -raw init)
tofu apply
tofu output -raw next_steps
```

`next_steps` says the rest, in order: the DNS records, how to tell the installation is up (about
ten minutes the first time) and where to look if it is not, and the first sign-in - `admin@<domain>`
(`admin_email`) with a one-time password this apply wrote to SSM.

## Updating

Change `spin_version` and `spin_boot_sha256` in `terraform.tfvars` to the new release's, then:

```bash
tofu plan     # the launch templates and the documents change, and nothing else
tofu apply
```

Each machine is replaced beside itself, and the old one serves until the new one does. How it
went is `tofu output update_status`: `Successful`; or `RollbackSuccessful` with the reason, in which
case the old machine is still serving and `tofu output boot_log` says why the new one did not come
up. A change to anything else a machine starts on - `installation_config`, the autoscaling
settings - rolls out the same way.

A release older than the one that last started the catalog refuses to start on it: going back past
a change to the schema is a restore of the catalog (spin's `controlplane catalog restore`), not an
update.

## Removing an installation

The encryption key and the CA refuse to be destroyed, because an apply that replaced either would
leave an installation nothing can open. To remove one on purpose:

```bash
tofu apply -var 'database={deletion_protection=false}'
tofu state rm module.spin.module.controlplane.aws_ssm_parameter.encryption_key \
  module.spin.module.controlplane.tls_private_key.ca module.spin.module.controlplane.tls_self_signed_cert.ca
tofu destroy
aws ssm delete-parameter --name /<name>/controlplane-encryption-key
```

The destroy stops at the volumes' bucket: every object in it is under Object Lock, and spin puts
a legal hold on what it publishes. To remove it now rather than when the retention
(`object_lock_days`) runs out, lift the holds and delete every version bypassing the governance
retention - with credentials allowed `s3:PutObjectLegalHold` and `s3:BypassGovernanceRetention` -
then destroy again:

```bash
B=<name>-volumes-<account>-<region>
aws s3api list-object-versions --bucket $B --query 'Versions[].[Key,VersionId]' --output text |
  while IFS=$'\t' read -r k v; do aws s3api put-object-legal-hold --bucket $B --key "$k" --version-id "$v" --legal-hold Status=OFF; done
aws s3api list-object-versions --bucket $B --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' --output json > /tmp/v.json
aws s3api delete-objects --bucket $B --bypass-governance-retention --delete file:///tmp/v.json
tofu destroy
```

What is left is the catalog's final snapshot. Install the next one under another `name`.

## What it decides, and why

- **A machine is told where its document is, and nothing else.** Every machine's user data is
  the same five lines: fetch `spin-boot` from the release's public package
  (`ghcr.io/spin-stack/spin-release`) by the digest pinned in `spin_boot_sha256`, check it, and
  run it with its role and the SSM parameter its document is in. Everything else - the release,
  the catalog, the name it takes, the collector - is in that document, and every step is
  `spin-boot`'s, in Go with tests (spin's `internal/boot`). `spin-boot` fetches the release's
  files and checks that spin's `release.yml` signed them at the version's tag before anything in
  them runs. Nothing is a container: each role is a binary under systemd, as its own user.
- **This apply writes every parameter, and no machine writes one.** The documents, the
  installation's configuration, the CA, the encryption key and the first administrator's
  password are all this module's; the permissions boundary denies every role of the
  installation `ssm:PutParameter`. A machine that was taken cannot leave a value for the next
  one to start on. The one parameter the operator writes is the collector's token.
- **The encryption key and the first password never reach the state.** Both are ephemeral values
  written through write-only attributes, once (`value_wo_version`). The key is, with the
  catalog, the installation: a new one is a catalog nothing can open, so nothing here makes one
  again. The CA is in the state on purpose - its certificate is in the proxy's and the runners'
  documents - so **encrypt the state** (OpenTofu's `encryption` block; a KMS key is the simplest).
- **Runners join by who they are.** A runner signs a GetCallerIdentity with its instance role,
  bound to this installation and to its host id, and the control plane asks STS whose signature
  it is (spin's `internal/domain/hostjoin`). The installation's configuration names the runners'
  role and the policy its machines start under (`runner_policy`: a spot reclaim announced by
  AWS and 100 seconds to empty itself). There is no token to mint, rotate or publish, and the
  runners' role reads its own document and nothing else.
- **A runner installs its control plane's release**, asked of the control plane once it has
  joined, not one this module is given: while an update replaces the control plane - or after
  one is abandoned - a runner of the new release would be refused by the old. A `spin-boot` of
  another release than the control plane's fetches that release's `spin-boot`, checked the same
  way, and hands over to it.
- **No NAT gateway, no interface endpoints.** Every machine has a public address in a public
  subnet, and the bucket is reached through the S3 gateway endpoint, which is free. A NAT is
  $32 a month and a charge per GB before a workspace runs; an interface endpoint is $7 a
  month per zone each. A public address is not an open door: each machine's security group is
  what the internet may reach of it, and for all but one of them that is nothing.
- **The proxy is the only machine the internet reaches**, on 80 and 443, and it holds nothing
  but its own certificates and the CA certificate it trusts the control plane by. The control
  plane has no rule for the internet at all - its public address is a way out - and its 8080
  answers the proxy and the runners alone; the proxy may reach the control plane on 8080 and the
  web on 80 and 443, and nothing else. A runner has no ingress. None of them has SSH: Session
  Manager is the way in, and IMDSv2 is required everywhere.
- **Inside the VPC the components are names.** A private zone, `internal_zone`
  (`spin.internal`, $0.50 a month), holds `cp.` and `proxy.` with a ten-second TTL, each
  written by the machine it names: the control plane's certificate carries `cp.spin.internal`,
  and the proxy, the runners and the collector's clients dial it, so a machine replaced is a
  record changed rather than an address in every runner's configuration. The runners reach the
  relay at `proxy.spin.internal` too, checking its certificate as `tunnel.app.<domain>`, so the
  relay never leaves the VPC and the proxy's 443 need not be open to wherever runners happen to
  be: `proxy_allowed_cidrs` can be the users' networks alone (80 stays open for the ACME
  challenge). `route53_zone_id` only writes the public records where the installation keeps its
  DNS there, and with it elsewhere they are the operator's, pointed at the `proxy_ip` output.
- **An update is a machine beside the old one, not a stop.** The control plane and the proxy
  are each an autoscaling group of one, and a change to what a machine is - `spin_version`, the
  image, the size - is a new launch template the group's instance refresh rolls out at 100%
  healthy: the new machine starts before the old one is retired, and a launch hook holds the
  refresh until it says it serves, abandoning it - and keeping the old - if it never does. A new
  control plane points `cp.` at itself and starts, which takes the term: the old one,
  superseded, closes and stays down, and runners and the proxy reconnect within seconds while
  every workspace runs on. A new control plane that fails before it is in service hands the
  installation back: its control plane stopped, `cp.` pointed where it was, the launch
  abandoned. Each control plane machine then runs `spin-boot watch`, which keeps its control
  plane to whose the name is - serving it when the name is its own, which is how the old one
  takes the term back; taking the name back when the machine it points at has answered nothing
  for fifteen minutes; asking to be replaced when it cannot serve for ten. A new proxy puts back
  the certificates the last one had from their own bucket (versioned, no Object Lock), starts
  Caddy, and once Caddy answers points `proxy.` at itself and takes the elastic IP; its watch
  saves what Caddy issues every five minutes, following no link out of Caddy's directory. What
  is lost is seconds of API and open connections, never a workspace. Canonical publishing a
  newer image is such a change too: an apply after it rolls both machines onto it. A change to a
  document alone reaches a machine when it next starts: `aws autoscaling
  start-instance-refresh` on its group.
- **The proxy has subnets of its own**, and the control plane takes a browser's address only
  from them (`trusted_proxies`, declared in the installation's configuration): a runner,
  elsewhere in the VPC, cannot pass as the proxy.
- **No role can make itself more.** Every role both modules create carries one permissions
  boundary: none may write IAM or pass a role, assume any role but the runner scope, touch the
  VPC's network or a security group, write a parameter, run commands on another machine through
  SSM, or lift the bucket's lock or the logs. A policy attached later, by mistake or from a
  machine that was taken, cannot grant past it.
- **The control plane's secrets are its role's alone.** Session Manager is given as a policy of
  this module's - the agent's registration and its channels - and not AWS's
  `AmazonSSMManagedInstanceCore`, which also reads every parameter in the account: the
  parameters are under the account's `aws/ssm` key, so on the proxy or a runner it opened the
  encryption key. The boundary backs this: no role but the control plane's reads the key, the
  CA's key, the first password, the installation's configuration or the collector's token.
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
  the above - the user data, the documents, the secrets, the ingress rules, IMDSv2, encryption,
  the bucket's lock and policy, the roles and their boundary - and `task lint` runs it with the
  format check and validation, in CI on every push.
- **The bucket answers object requests only through that endpoint.** A runner's credential is
  minted by the control plane for an hour and scoped to its volumes; copied off the machine,
  it opens nothing. Bucket-level calls stay open to the account, so this module can still be
  applied from outside the VPC.
- **The control plane's role cannot lift the lock.** It may not bypass a retention, rewrite
  the bucket's policy or change its Object Lock rule. Spin writes the bucket's lifecycle rules
  itself, so this module declares none.
- **The control plane sizes the group, not a schedule or a metric.** It is the one that knows a
  workspace is waiting for a host, and that the last one stopped an hour ago. The first create
  or start of the day waits in *Waiting for a host* for the few minutes a runner takes to boot
  and install; the control plane has asked the group for one, and places the workspace on it
  when it registers. It only ever goes from none to one, adds one while a workspace has waited
  longer than a host takes to come, and goes back to none: it never picks one host of several
  to take away, since the group would choose which. Its role may resize that one group and
  nothing else, and the group's name, `<name>-runners`, is the contract between the modules.
- **The installation's configuration is this module's.** `installation_config` is the
  installation's config file (spin's `configs/spin-example.yaml`); this module adds the domain,
  who joins as a host and the autoscaling settings, and writes it where the control plane reads
  it at every start. It is then the file's one author.
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
  role signs and owns the database.
- **Small machines.** The control plane and the proxy are `t8i.micro` by default: with the
  catalog on RDS, the control plane is the control plane alone (and Alloy, where there is a
  collector - `t8i.small` there for a busy fleet). Two of them and the database are the whole
  standing cost when no runner is up.

Hosts outside the group are still added the ordinary way - a one-time token from Admin → Hosts
and `spin-install runner` - and are policed by the same control plane.
