resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${var.name}/connections"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "client-vpn-connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

# Controls what VPN clients can reach after the tunnel is up
resource "aws_security_group" "vpn" {
  name        = "${var.name}-vpn-sg"
  description = "Client VPN endpoint — egress scoped to VPC only"
  vpc_id      = var.vpc_id

  egress {
    description = "VPN clients to VPC resources only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn-sg" })
}

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "${var.name} admin VPN"
  client_cidr_block      = var.client_cidr_block
  server_certificate_arn = var.server_certificate_arn
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.vpn.id]
  split_tunnel           = true   # only VPC-bound traffic goes through the tunnel
  transport_protocol     = "udp"
  vpn_port               = 443
  session_timeout_hours  = 8

  # Factor 1: mutual TLS — admin must present a valid client certificate
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_certificate_arn
  }

  # Factor 2: SAML federation — Cognito admin pool enforces TOTP MFA
  authentication_options {
    type              = "federated-authentication"
    saml_provider_arn = var.saml_provider_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  tags = merge(var.tags, { Name = "${var.name}-client-vpn" })
}

# One association per AZ for high availability; each one auto-creates a local
# route for that subnet's CIDR in the VPN routing table.
resource "aws_ec2_client_vpn_network_association" "private" {
  count                  = length(var.private_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = var.private_subnet_ids[count.index]
}

# Authorise all authenticated users to reach the entire VPC CIDR.
# Access is already narrowed by the Cognito admin pool + mutual TLS.
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Admin VPN — full VPC access"

  depends_on = [aws_ec2_client_vpn_network_association.private]
}
