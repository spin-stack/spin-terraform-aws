-- The role the control plane signs in as, made by the master user once and harmless again: it
-- authenticates with an IAM token alone (rds_iam), and owns the database, and with it the public
-- schema the control plane brings to schema.sql. The master keeps its password, in Secrets
-- Manager, for a person who needs it.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'spin') THEN
    CREATE ROLE spin LOGIN;
  END IF;
END
$$;
GRANT rds_iam TO spin;
-- The master may hand the database over only to a role it is a member of, and is a member for
-- that one statement: rds_iam reaches it through the membership, and a user RDS knows as an IAM
-- one it will not take a password from at all - the master's own, from Secrets Manager, which
-- is how every later boot runs this file.
GRANT spin TO CURRENT_USER;
ALTER DATABASE spin OWNER TO spin;
REVOKE spin FROM CURRENT_USER;
