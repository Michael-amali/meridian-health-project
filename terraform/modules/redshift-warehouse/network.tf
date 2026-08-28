# Phase 6: a small dedicated VPC just for the Redshift Serverless workgroup -
# Redshift Serverless requires the workgroup to sit in subnets across at
# least 3 AZs, even though there's no cluster to manage. Private subnets
# only, no IGW/NAT: nothing here needs general outbound internet access, and
# every DDL/load/query statement this module and the Step Functions
# pipelines run goes through the Redshift Data API (an AWS API call made
# from outside the VPC), not a network path into these subnets. The one
# thing Redshift's own compute genuinely needs from inside the VPC is a way
# to read S3 for COPY - the S3 gateway endpoint below covers that for free,
# without a NAT gateway.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  subnet_azs   = slice(data.aws_availability_zones.available.names, 0, 3)
  subnet_cidrs = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
}

resource "aws_vpc" "redshift" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "meridian-redshift-vpc-${var.env}" })
}

resource "aws_subnet" "redshift" {
  count = 3

  vpc_id            = aws_vpc.redshift.id
  cidr_block        = local.subnet_cidrs[count.index]
  availability_zone = local.subnet_azs[count.index]

  tags = merge(var.tags, { Name = "meridian-redshift-subnet-${count.index}-${var.env}" })
}

# Local-only route table, explicit rather than relying on the VPC's implicit
# default one - the S3 endpoint route below is added directly to this table.
resource "aws_route_table" "redshift_private" {
  vpc_id = aws_vpc.redshift.id

  tags = merge(var.tags, { Name = "meridian-redshift-rt-${var.env}" })
}

resource "aws_route_table_association" "redshift" {
  count = 3

  subnet_id      = aws_subnet.redshift[count.index].id
  route_table_id = aws_route_table.redshift_private.id
}

# Gateway endpoints have no hourly cost and don't need a security group (they
# route via a prefix list on the route table, not an ENI) - this is what lets
# COPY reach the curated bucket without a NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.redshift.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.redshift_private.id]

  tags = merge(var.tags, { Name = "meridian-redshift-s3-endpoint-${var.env}" })
}

data "aws_region" "current" {}

resource "aws_security_group" "redshift" {
  name        = "meridian-redshift-${var.env}"
  description = "Redshift Serverless workgroup - internal traffic and S3 endpoint access only"
  vpc_id      = aws_vpc.redshift.id

  tags = merge(var.tags, { Name = "meridian-redshift-sg-${var.env}" })
}

# Self-referencing ingress + egress on every protocol/port - AWS's own
# guidance for a Redshift security group is to allow all traffic to/from
# itself, since the workgroup's own compute needs unrestricted internal
# communication across the 3 subnets above.
resource "aws_vpc_security_group_ingress_rule" "redshift_self" {
  security_group_id            = aws_security_group.redshift.id
  referenced_security_group_id = aws_security_group.redshift.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "redshift_self" {
  security_group_id            = aws_security_group.redshift.id
  referenced_security_group_id = aws_security_group.redshift.id
  ip_protocol                  = "-1"
}

# Separate, narrower egress rule for the one thing Redshift's compute needs
# to reach outside the security group: the S3 gateway endpoint above, scoped
# to S3's own prefix list rather than a blanket 0.0.0.0/0 - there's no
# NAT/IGW for that rule to reach anywhere else anyway.
resource "aws_vpc_security_group_egress_rule" "redshift_to_s3" {
  security_group_id = aws_security_group.redshift.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
