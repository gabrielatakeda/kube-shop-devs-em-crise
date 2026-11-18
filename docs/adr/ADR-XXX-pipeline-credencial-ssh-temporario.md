# ADR-XXX: Pipeline com usuário IAM dedicado e SSH temporário via bastion

> Renumerar seguindo a sequência dos ADRs da Entrega 1.

- **Status:** aceita
- **Data:** 18/11/2026
- **Relacionados:** `bootstrap/main.tf`, `.github/workflows/infra-deploy.yml`, `ops.yml`, `infra-destroy.yml`

## Contexto

A PM-04 exige que toda mudança passe pela pipeline (Terraform e Ansible em sequência, com parâmetros), com credenciais em Secrets. A Entrega 2 exige SSH só de um CIDR específico (R7) e proíbe credencial no código. O runner do GitHub Actions tem IP dinâmico e precisa de SSH para o Ansible.

A primeira versão desta decisão autenticava a pipeline por **OIDC** (role IAM sem chave armazenada). No bootstrap, a conta do grupo recusou criar, listar e consultar provedores OIDC (`iam:CreateOpenIDConnectProvider`, `iam:ListOpenIDConnectProviders`, `iam:GetOpenIDConnectProvider`) por um *explicit deny* da SCP da organização do curso (`p-k9zu5moj`). Com orientação do professor, a pipeline passou a usar access key.

## Decisão (Y-statement)

No contexto de automatizar o provisionamento e a configuração pelo GitHub Actions, diante do bloqueio de OIDC pela SCP do curso e da necessidade de manter o SSH restrito, decidimos:
- **autenticar a pipeline com a access key de um usuário IAM dedicado** (`kubeshop-github-actions`), criado no bootstrap, sem acesso ao console e com política inline limitada a EC2/VPC na região e a recursos S3/SSM/IAM/KMS com prefixo `kubeshop-`; a chave fica **somente** nos GitHub Secrets `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`;
- **abrir, a cada execução, uma regra SSH /32 para o IP do runner no SG do bastion**, com tag `temporario=pipeline`, e revogá-la num passo `if: always()`;
- manter essa regra **fora do Terraform**, com as regras gerenciadas como recursos separados, não blocos inline.

Descartamos:
- **OIDC com role IAM:** era a opção preferida (sem credencial longa), mas é bloqueada pela SCP da organização;
- **chaves do usuário IAM do grupo:** dariam à pipeline todas as permissões dos integrantes;
- **liberar as faixas de IP do GitHub:** milhares de CIDRs compartilhados com outros clientes;
- **runner auto-hospedado:** mais uma VM para manter e pagar.

Com isso, nenhuma credencial AWS fica no repositório, o SSH continua fechado fora das execuções e o `terraform plan` seguinte não mostra divergência. **Aceitamos que:**
- existe uma **credencial de longa duração**: se vazar, dá acesso às permissões da pipeline até ser revogada. Mitigações: escopo mínimo da política, GitHub mascara secrets nos logs, Gitleaks em toda execução e rotação com `terraform apply -replace=aws_iam_access_key.github_actions` no `bootstrap` (seguida da troca dos secrets);
- a secret key também fica no state local do bootstrap (`bootstrap/terraform.tfstate`, ignorado pelo Git e nunca compartilhado);
- durante alguns minutos a porta 22 do bastion aceita o IP de um runner;
- se o passo de revogação falhar, a regra fica até a próxima execução do `infra-destroy` (que remove regras com a tag) ou até a remoção manual;
- quem tem permissão de escrita no repositório pode executar as pipelines.

## Consequências

- Variáveis no GitHub: `TF_STATE_BUCKET`, `AWS_REGION`, `SSH_ALLOWED_CIDR`; secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SSH_PRIVATE_KEY`, `SSH_PUBLIC_KEY`.
- Um ambiente nunca é alterado por duas execuções ao mesmo tempo (`concurrency`) e o state tem lock no S3 (`use_lockfile`).
- Evolução: se a SCP passar a permitir OIDC, voltar à role com trust policy restrita ao repositório e apagar o usuário. SSM Run Command / Session Manager eliminam o SSH da pipeline.
