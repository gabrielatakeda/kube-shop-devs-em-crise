# Uso de IA

> Atualizar a cada entrega. Registrar o que foi feito com IA, o que foi revisado ou alterado pelo grupo e o que foi feito sem IA.

## Entrega 2 / PM-04 (novembro de 2026)

**Ferramenta:** Claude (Anthropic), via Claude Code, como assistente de engenharia.

| Atividade | Uso de IA | Revisão / responsabilidade do grupo |
|---|---|---|
| Comparação das entregas e escolha do escopo | Análise dos PDFs e plano unificado | Decisão do escopo (KubeShop) e da divisão das tarefas pelo grupo |
| Terraform (`bootstrap/`, `infra/`) | Geração do código a partir dos requisitos R1–R11, S2, S4–S6 e B6 | *(descrever: revisão linha a linha, mudanças feitas, testes de apply/destroy)* |
| Ansible (`ansible/`) | Geração das roles e do playbook de operação | *(descrever)* |
| Pipelines (`.github/workflows/`) | Geração dos workflows | *(descrever)* |
| Tratamento dos achados de segurança | Execução local de Trivy/Checkov, proposta de correção (CMK) e de justificativas para os aceites | *(descrever quais justificativas o grupo revisou ou alterou)* |
| Documentação (`docs/`) | Rascunhos de segurança, HA, backup, custos, ADRs, manual | *(descrever: conferência dos preços na calculadora, ajustes com a Entrega 1)* |

## Validações feitas com apoio da IA (antes do deploy real)

`terraform validate`/`fmt`, Trivy, Checkov, Gitleaks, ansible-lint (perfil production), actionlint, `docker compose config`, `nginx -t`, `sshd -t` e teste de backup/restore com MongoDB 8.0.17 local.

## Limites e cuidados

- Os preços em `docs/custos/` são valores de referência e **precisam ser confirmados na AWS Pricing Calculator**.
- A IA não teve acesso às credenciais AWS da pipeline, às chaves SSH nem aos segredos; nenhum valor sensível foi compartilhado.
- O grupo é responsável por entender e defender todo o código e as decisões na defesa técnica.
