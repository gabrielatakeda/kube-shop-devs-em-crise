output "tf_state_bucket" {
  description = "Cadastrar no GitHub como variável TF_STATE_BUCKET."
  value       = aws_s3_bucket.tfstate.bucket
}

output "aws_access_key_id" {
  description = "Cadastrar no GitHub como secret AWS_ACCESS_KEY_ID."
  value       = aws_iam_access_key.github_actions.id
}

# Ver com: terraform output -raw aws_secret_access_key
output "aws_secret_access_key" {
  description = "Cadastrar no GitHub como secret AWS_SECRET_ACCESS_KEY."
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}
