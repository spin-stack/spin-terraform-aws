# What this module promises about the browser terminal, held against its plan with no account: what
# it publishes is the release's files and only them, each as what it is, readable through the
# distribution alone, written by no role of the installation, under a policy that lets the page
# reach the dashboard's API and the relay and nothing else.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "aws" {
  alias                       = "us_east_1"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_resource {
  target = aws_cloudfront_distribution.terminal
  values = { arn = "arn:aws:cloudfront::123456789012:distribution/E0TERM" }
}

variables {
  name     = "spin"
  iam_name = "spin-us-east-2"
  domain   = "spinbox.dev"
  zone_id  = "Z0SPINPUBLIC"
  release  = "v20261003.1"
  files    = "tests/term"
}

run "the_terminal_publishes_the_releases_files_and_nothing_else" {
  command = plan

  assert {
    condition     = output.url == "https://term.spinbox.dev"
    error_message = "the terminal is not term.<domain>"
  }
  assert {
    condition = (
      toset(keys(aws_s3_object.file)) == toset(["index.html", "term.wasm", "wasm_exec.js", "assets/index-abc123.js"]) &&
      aws_s3_object.file["term.wasm"].content_type == "application/wasm" &&
      aws_s3_object.file["index.html"].content_type == "text/html; charset=utf-8" &&
      aws_s3_object.file["wasm_exec.js"].content_type == "text/javascript" &&
      aws_s3_object.file["term.wasm"].etag == filemd5("tests/term/term.wasm")
    )
    error_message = "what is published is not the release's files, each as what it is, or carries what term:fetch wrote beside them"
  }
  assert {
    condition = (
      aws_s3_object.file["assets/index-abc123.js"].cache_control == "public, max-age=31536000, immutable" &&
      aws_s3_object.file["index.html"].cache_control == "no-cache" &&
      aws_s3_object.file["term.wasm"].cache_control == "no-cache"
    )
    error_message = "a file whose name outlives a release is cached past it"
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.terminal.block_public_acls && aws_s3_bucket_public_access_block.terminal.block_public_policy &&
      aws_s3_bucket_public_access_block.terminal.ignore_public_acls && aws_s3_bucket_public_access_block.terminal.restrict_public_buckets
    )
    error_message = "the bucket can be made public other than through the distribution"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.terminal.statement :
      s.effect == null && toset(s.actions) == toset(["s3:GetObject"]) &&
      anytrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudfront.amazonaws.com"])]) &&
    anytrue([for c in s.condition : c.variable == "AWS:SourceArn" && toset(c.values) == toset(["arn:aws:cloudfront::123456789012:distribution/E0TERM"])])])
    error_message = "the distribution does not read the files, or something else does"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.terminal.statement :
      s.effect == "Deny" && contains(s.actions, "s3:PutObject*") && contains(s.actions, "s3:DeleteObject*") && contains(s.actions, "s3:PutBucket*") &&
    anytrue([for c in s.condition : c.test == "ArnLike" && c.variable == "aws:PrincipalArn" && toset(c.values) == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-*"])])])
    error_message = "a role of the installation may write the code that asks a person's passkey"
  }
  assert {
    condition = alltrue([for h in aws_cloudfront_response_headers_policy.terminal.security_headers_config :
      alltrue([for c in h.content_security_policy :
        strcontains(c.content_security_policy, "default-src 'none'") &&
        strcontains(c.content_security_policy, "connect-src 'self' https://app.spinbox.dev wss://tunnel.app.spinbox.dev") &&
        strcontains(c.content_security_policy, "script-src 'self' 'wasm-unsafe-eval'") &&
        strcontains(c.content_security_policy, "frame-ancestors 'none'") && c.override
    ])])
    error_message = "the page may reach more than the dashboard's API and the relay, run another's script, or be framed"
  }
  assert {
    condition = (
      aws_cloudfront_distribution.terminal.aliases == toset(["term.spinbox.dev"]) &&
      alltrue([for b in aws_cloudfront_distribution.terminal.default_cache_behavior :
      b.viewer_protocol_policy == "https-only" && toset(b.allowed_methods) == toset(["GET", "HEAD"])])
    )
    error_message = "the terminal is served at another name, over plain HTTP, or takes more than reads"
  }
}

run "files_of_another_release_are_refused" {
  command = plan

  variables {
    release = "v20261004.1"
  }

  expect_failures = [aws_s3_object.file]
}
