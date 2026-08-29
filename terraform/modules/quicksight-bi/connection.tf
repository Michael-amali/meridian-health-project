# Phase 7: how QuickSight reaches Redshift.
#
# The Phase 6 workgroup is publicly_accessible = false and sits in a private
# VPC with no NAT or internet gateway (modules/redshift-warehouse/network.tf),
# so QuickSight cannot connect to it the ordinary way. A QuickSight VPC
# connection is the supported answer: QuickSight puts its own network
# interfaces inside our subnets and queries Redshift over a private address.
# Nothing about the workgroup's network posture has to be loosened for this.

data "aws_vpc" "redshift" {
  id = var.redshift_vpc_id
}

resource "aws_iam_role" "vpc_connection" {
  name = "meridian-quicksight-vpc-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "quicksight.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# The exact permission set QuickSight needs to manage the network interfaces
# it places in our subnets - it creates one per subnet when the connection is
# created and deletes them when it is destroyed.
resource "aws_iam_role_policy" "vpc_connection" {
  name = "manage-network-interfaces"
  role = aws_iam_role.vpc_connection.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
        ]
        Resource = "*"
      }
    ]
  })
}

# A security group of its own rather than reusing the Redshift one. The
# Redshift group only allows traffic to and from itself plus the S3 endpoint
# (see network.tf), and QuickSight's interfaces need one thing that rule
# shape can't express: DNS lookups against the VPC resolver, which is not a
# member of any security group.
resource "aws_security_group" "quicksight" {
  name        = "meridian-quicksight-${var.env}"
  description = "QuickSight VPC connection interfaces - outbound to Redshift and the VPC DNS resolver only"
  vpc_id      = var.redshift_vpc_id

  tags = merge(var.tags, { Name = "meridian-quicksight-sg-${var.env}" })
}

resource "aws_vpc_security_group_egress_rule" "quicksight_to_redshift" {
  security_group_id            = aws_security_group.quicksight.id
  referenced_security_group_id = var.redshift_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.redshift_endpoint_port
  to_port                      = var.redshift_endpoint_port
  description                  = "Query the Redshift Serverless workgroup"
}

# The workgroup endpoint is a DNS name, so the interfaces have to be able to
# resolve it before they can connect to anything. The VPC's Route 53 resolver
# lives at a fixed address inside the VPC's own CIDR, and answers on both UDP
# and TCP - large answers fall back to TCP.
resource "aws_vpc_security_group_egress_rule" "quicksight_dns_udp" {
  security_group_id = aws_security_group.quicksight.id
  cidr_ipv4         = data.aws_vpc.redshift.cidr_block
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  description       = "Resolve the workgroup endpoint via the VPC DNS resolver"
}

resource "aws_vpc_security_group_egress_rule" "quicksight_dns_tcp" {
  security_group_id = aws_security_group.quicksight.id
  cidr_ipv4         = data.aws_vpc.redshift.cidr_block
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  description       = "Resolve the workgroup endpoint via the VPC DNS resolver (TCP fallback)"
}

# QuickSight's network interfaces do not track connection state the way an
# EC2 instance's do, so the usual "allow it out and the reply comes back"
# assumption does not hold here - every reply needs its own inbound rule.
# This is the single most common reason a QuickSight VPC connection creates
# cleanly and then fails its first connection attempt with nothing more
# specific than "The connection attempt failed", which is exactly what
# happened when this module was first applied.
resource "aws_vpc_security_group_ingress_rule" "quicksight_redshift_replies" {
  security_group_id            = aws_security_group.quicksight.id
  referenced_security_group_id = var.redshift_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  description                  = "Replies from Redshift, which arrive on an ephemeral port"
}

resource "aws_vpc_security_group_ingress_rule" "quicksight_dns_replies" {
  security_group_id = aws_security_group.quicksight.id
  cidr_ipv4         = data.aws_vpc.redshift.cidr_block
  ip_protocol       = "udp"
  from_port         = 1024
  to_port           = 65535
  description       = "Replies from the VPC DNS resolver"
}

# The matching inbound rule on the Redshift side. This is the one change this
# module makes to a Phase 6 resource, and it is the narrowest possible: port
# 5439 from this module's security group only.
resource "aws_vpc_security_group_ingress_rule" "redshift_from_quicksight" {
  security_group_id            = var.redshift_security_group_id
  referenced_security_group_id = aws_security_group.quicksight.id
  ip_protocol                  = "tcp"
  from_port                    = var.redshift_endpoint_port
  to_port                      = var.redshift_endpoint_port
  description                  = "QuickSight VPC connection"
}

resource "aws_quicksight_vpc_connection" "this" {
  vpc_connection_id  = "meridian-redshift-${var.env}"
  name               = "meridian-redshift-${var.env}"
  role_arn           = aws_iam_role.vpc_connection.arn
  security_group_ids = [aws_security_group.quicksight.id]
  subnet_ids         = var.redshift_subnet_ids

  tags = var.tags

  # Creating the connection provisions and health-checks one network
  # interface per subnet, which routinely takes several minutes - well past
  # the provider's default.
  timeouts {
    create = "20m"
    delete = "20m"
  }
}

resource "aws_quicksight_data_source" "redshift" {
  data_source_id = "meridian-redshift-${var.env}"
  name           = "Meridian Redshift (${var.env})"
  type           = "REDSHIFT"

  parameters {
    redshift {
      host     = var.redshift_endpoint_address
      port     = var.redshift_endpoint_port
      database = var.redshift_database_name
    }
  }

  # The password is the one generated in redshift-setup.tf, so it is already
  # in Terraform state either way - pointing QuickSight at the Secrets
  # Manager copy instead would mean creating and maintaining QuickSight's own
  # magically-named secrets-access role, which is more moving parts for no
  # real change in exposure.
  credentials {
    credential_pair {
      username = local.reader_user
      password = random_password.reader_user.result
    }
  }

  vpc_connection_properties {
    vpc_connection_arn = aws_quicksight_vpc_connection.this.arn
  }

  permission {
    principal = local.admin_user_arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
  }

  tags = var.tags

  depends_on = [aws_redshiftdata_statement.reader_user]
}
