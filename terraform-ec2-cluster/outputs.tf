# --- OUTPUT THE DNS NAME ---
output "database_endpoint" {
  value       = aws_lb.haproxy_nlb.dns_name
  description = "The single DNS endpoint your applications will use to connect to the database."
}



# Output the bucket name so you can copy it easily!
output "ansible_ssm_bucket_name" {
  value = aws_s3_bucket.ansible_ssm_bucket.bucket
}


