# Configuração parcial: bucket, key e region são informados no init.
#   terraform init \
#     -backend-config="bucket=<TF_STATE_BUCKET>" \
#     -backend-config="key=kubeshop/<environment>/terraform.tfstate" \
#     -backend-config="region=us-east-2"
# Cada ambiente (dev/homolog/prod) tem seu próprio state.
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
