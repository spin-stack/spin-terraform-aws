# The database: Postgres on RDS, in subnets of its own that have no route out of the VPC, reached
# on 5432 from the control plane's group alone. No password of it is anywhere Terraform writes:
# the master's is RDS's own, in Secrets Manager, and used once by the control plane's first boot
# to make the role the control plane signs in as - spin, which authenticates with an IAM token
# its machine's role signs (SPIN_CP_DATABASE_AUTH=aws-iam) and owns the database.

resource "aws_subnet" "database" {
  count             = length(local.zones)
  vpc_id            = aws_vpc.this.id
  availability_zone = local.zones[count.index]
  # /24s from the top half of the VPC, where the public /20s are the bottom half; the proxy's
  # are beside them (proxy.tf).
  cidr_block = cidrsubnet(var.vpc_cidr, 8, 128 + count.index)
  tags       = merge(local.tags, { Name = "${var.name}-database-${local.zones[count.index]}" })
}

# No route but the VPC's own: a database that cannot reach the internet cannot be made to send
# its rows to it.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-database" })
}

resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# The names in AWS — the instance, its subnet group, its security group's description — keep the
# word the installation was first made with: changing any of them replaces the resource, and the
# instance's replacement is the database's.
resource "aws_db_subnet_group" "database" {
  name       = "${var.name}-catalog"
  subnet_ids = aws_subnet.database[*].id
  tags       = local.tags
}

resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "spin catalog: 5432 from the control plane only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-database" })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_controlplane" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.controlplane.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "the control plane"
}

resource "aws_vpc_security_group_egress_rule" "controlplane_to_database" {
  security_group_id            = aws_security_group.controlplane.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "the database"
}

resource "aws_db_instance" "database" {
  identifier     = "${var.name}-catalog"
  engine         = "postgres"
  engine_version = var.database.engine_version
  instance_class = var.database.instance_class

  allocated_storage     = var.database.storage_gb
  max_allocated_storage = var.database.max_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "spin"
  username = "spin_admin"
  # RDS makes it and keeps it in Secrets Manager: never in this state, never in user data.
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database.multi_az

  # RDS's own backups beside the control plane's hourly database backup in the bucket: a point
  # in time to restore to, and a snapshot when the instance is deleted.
  backup_retention_period = var.database.backup_retention_days
  copy_tags_to_snapshot   = true
  deletion_protection     = var.database.deletion_protection
  skip_final_snapshot     = false
  # Named for this installation's state, not only its name: an installation destroyed and made
  # again under the same name would otherwise find the last one's snapshot in the way, and fail
  # the destroy it needs to finish.
  final_snapshot_identifier = "${var.name}-catalog-final-${random_id.database.hex}"

  # Which statements take the time, and waiting on what: the control plane's traces time each
  # query from its side, which cannot tell a statement waiting on the disk of a burstable
  # instance from one waiting on a lock. Seven days is the retention that costs nothing.
  performance_insights_enabled          = var.database.insights
  performance_insights_retention_period = var.database.insights ? 7 : null

  auto_minor_version_upgrade = true
  # A change asked for is made by the apply that asks for it, not at a maintenance window the
  # operator never chose; a major version is one such change.
  apply_immediately           = var.database.apply_immediately
  allow_major_version_upgrade = true
  tags                        = local.tags
}

resource "random_id" "database" {
  byte_length = 4
}

moved {
  from = aws_db_subnet_group.catalog
  to   = aws_db_subnet_group.database
}

moved {
  from = aws_db_instance.catalog
  to   = aws_db_instance.database
}

moved {
  from = random_id.catalog
  to   = random_id.database
}

locals {
  database_url = "postgres://spin@${aws_db_instance.database.address}:${aws_db_instance.database.port}/spin?sslmode=verify-full"
}
