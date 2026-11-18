# Evidências

Salvar aqui os arquivos citados em `docs/validacao.md`, **sem dados sensíveis** (cortar ID da conta, e-mails e chaves das capturas).

| Arquivo sugerido | Origem |
|---|---|
| `s8-mfa.png` | Console IAM, usuário com MFA atribuído (S8) |
| `orcamento.png` | Billing → Budgets, alerta criado antes do 1º apply |
| `relatorios-iac/` | Artefato `relatorios-iac` do workflow `security` (Trivy, Checkov, achados aceitos) |
| `relatorio-gitleaks/` | Artefato `relatorio-gitleaks` |
| `cenario-1-plan.txt`, `cenario-1-ansible.log` | Artefatos `terraform-dev` e `ansible-dev` do 1º `infra-deploy` |
| `cenario-2-*`, `cenario-3-*` | Mesmos artefatos nas execuções seguintes |
| `d3-ssh.png` | Terminal: bastion, `ssh -J` e `Permission denied (publickey)` |
| `d4-nat.png` | Terminal na VM-DB: `curl ifconfig.me` = `nat_public_ip` |
| `backup-objeto.json`, `backup-lifecycle.json` | Artefato `ops-backup-*` |
| `restore-resultado.json` | Artefato `ops-restore-test-*` |
| `inventario-pos-destroy.md` | Artefato `evidencias-destroy-*` (até 48 h após a apresentação) |
| `custo-real.png` | Cost Explorer filtrado por `projeto = kubeshop` |
