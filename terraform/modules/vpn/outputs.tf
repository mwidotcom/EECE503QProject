output "endpoint_id"       { value = aws_ec2_client_vpn_endpoint.main.id }
output "endpoint_dns_name" { value = aws_ec2_client_vpn_endpoint.main.dns_name }
output "security_group_id" { value = aws_security_group.vpn.id }
output "client_cidr_block" { value = aws_ec2_client_vpn_endpoint.main.client_cidr_block }
