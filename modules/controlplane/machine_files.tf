# What each machine is given as files - its timers, their scripts, the collector's configuration
# and the installation's config - each a file under files/ and written where it goes by one
# generated block of the user data, so none of them is a heredoc to read inside a script. The
# proxy's are beside its machine (proxy.tf).

locals {
  controlplane_files = merge({
    "/usr/local/lib/spin/lifecycle.sh"           = { mode = "0644", content = local.lifecycle_sh["controlplane"] }
    "/usr/local/sbin/spin-controlplane-watchdog" = { mode = "0755", content = file("${path.module}/files/spin-controlplane-watchdog") }
    "/etc/systemd/system/spin-controlplane-watchdog.service" = {
      mode = "0644", content = file("${path.module}/files/spin-controlplane-watchdog.service")
    }
    "/etc/systemd/system/spin-controlplane-watchdog.timer" = {
      mode = "0644", content = file("${path.module}/files/spin-controlplane-watchdog.timer")
    }
    "/etc/spin-stack/installation.yaml" = { mode = "0600", content = yamlencode(local.installation) }
    "/etc/spin-stack/database-bootstrap.sql" = {
      mode = "0644", content = file("${path.module}/files/database-bootstrap.sql")
    }
    "/usr/local/sbin/spin-rotate-pool-token" = {
      mode = "0755"
      content = templatefile("${path.module}/files/spin-rotate-pool-token.tftpl", {
        name            = var.name
        region          = local.region
        token_parameter = local.token_parameter
        pool_flags      = join(" ", var.pool_token_flags)
        token_expiry    = "${tonumber(trimsuffix(var.pool_token_rotation, "h")) * 4}h"
      })
    }
    "/etc/systemd/system/spin-pool-token.service" = {
      mode = "0644", content = file("${path.module}/files/spin-pool-token.service")
    }
    "/etc/systemd/system/spin-pool-token.timer" = {
      mode = "0644", content = templatefile("${path.module}/files/spin-pool-token.timer.tftpl", { rotation = var.pool_token_rotation })
    }
    }, local.telemetry ? {
    "/etc/alloy/config.alloy" = {
      mode = "0644"
      content = templatefile("${path.module}/files/alloy.alloy.tftpl", {
        # Every address of a machine whose address is not fixed; the group's rules are who
        # reaches 4317 (telemetry.tf).
        listen        = "0.0.0.0"
        otlp_endpoint = var.grafana_cloud.otlp_endpoint
        instance_id   = var.grafana_cloud.instance_id
        log_severity  = var.grafana_cloud.log_severity
      })
    }
    "/etc/default/alloy" = { mode = "0644", content = file("${path.module}/files/alloy.default") }
    "/usr/local/sbin/spin-alloy-token" = {
      mode = "0755"
      content = templatefile("${path.module}/files/spin-alloy-token.tftpl", {
        region                  = local.region
        grafana_token_parameter = local.token_parameter_grafana
      })
    }
    "/etc/systemd/system/alloy.service.d/spin.conf" = { mode = "0644", content = file("${path.module}/files/alloy-spin.conf") }
    "/etc/systemd/system/spin-alloy-token.service"  = { mode = "0644", content = file("${path.module}/files/spin-alloy-token.service") }
    "/etc/systemd/system/spin-alloy-token.timer"    = { mode = "0644", content = file("${path.module}/files/spin-alloy-token.timer") }
  } : {})

  # Each role's files, as the lines of its user data that write them: one `install` per file,
  # its content in a quoted heredoc, so nothing in it is expanded by the shell, and a file that
  # ends without a newline still ends the heredoc.
  write_files = { for role, files in { controlplane = local.controlplane_files, proxy = local.proxy_files } :
    role => join("\n", [for p, f in files :
      "install -D -m ${f.mode} /dev/stdin '${p}' <<'SPIN_FILE'\n${trimsuffix(f.content, "\n")}\nSPIN_FILE"
    ])
  }
}
