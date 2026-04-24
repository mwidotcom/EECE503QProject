output "endpoint"          { value = aws_db_instance.main.endpoint }
output "address"           { value = aws_db_instance.main.address }
output "port"              { value = aws_db_instance.main.port }
output "db_name"           { value = aws_db_instance.main.db_name }
output "security_group_id" { value = aws_security_group.rds.id }
output "replica_endpoint"  { value = var.create_replica ? aws_db_instance.replica[0].endpoint : "" }
