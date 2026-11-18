# ADR-XXX: Estratégia de backup

> Renumerar seguindo a sequência dos ADRs da Entrega 1.

- **Status:** aceita (política mínima implantada; política GFS planejada)
- **Data:** 18/11/2026
- **Relacionados:** `docs/backup.md`, `infra/backup.tf`, `infra/iam.tf`, `ansible/roles/backup/`, `.github/workflows/ops.yml`

## Contexto

O único dado não reproduzível do KubeShop é o histórico de pedidos no MongoDB, que roda em VM (não gerenciado). A Entrega 2 exige uma política conservadora GFS (só planejada, com custo de 12 meses) e uma política mínima configurada por código, com retenção de até 2 dias, criptografia e ao menos uma cópia existente. O escopo do KubeShop exige backup automatizado e **restauração testada em ambiente isolado**.

## Decisão (Y-statement)

No contexto de proteger os pedidos do KubeShop contra exclusão acidental, corrupção e ataque, diante da exigência de RPO de 24 h e custo próximo de zero no período do trabalho, decidimos por:
- **dump lógico** (`mongodump --archive --gzip`) enviado em streaming para um **bucket S3 criptografado com a CMK do projeto**;
- **um prefixo por geração**, com **regra de ciclo de vida por prefixo**: GFS = `diario/` 7 dias em Standard, `semanal/` 5 semanas em Standard-IA, `mensal/` 12 meses em Glacier IR, com replicação para `us-east-1`;
- **política mínima** com só `diario/` e expiração em 2 dias;
- **VM do banco somente com `s3:PutObject` em `diario/*`**;
- **restauração feita pela pipeline num MongoDB descartável** no runner.

Descartamos:
- **snapshot do EBS (DLM):** só *crash-consistent*, cobra por GB de snapshot e restaurar exige recriar o volume;
- **AWS Backup:** custo por recurso protegido e não oferece dump lógico do MongoDB em VM.

Com isso, as cópias são consistentes do ponto de vista do banco, o backup é barato (< US$ 1/ano na GFS) e **um invasor na VM não consegue ler nem apagar os backups**. **Aceitamos que:**
- a política mínima não recupera erros percebidos depois de 2 dias;
- o destroy apaga as cópias junto com o ambiente (`backup_force_destroy`);
- a VM, por ter `PutObject`, pode gravar cópias falsas em `diario/`, o que é detectado pelo `restore-test`.

## Consequências

- O backup roda às 03:15 UTC (cron com `flock`) e sob demanda pela pipeline (`ops.yml → backup`), que confere criptografia e expiração.
- Usuário `backup` no MongoDB com o papel nativo `backup` (menor privilégio para o dump).
- O parâmetro de maior impacto no custo da GFS é a frequência diária combinada com a replicação entre regiões (`docs/backup.md`, B7).
- Para operação real: Object Lock (*governance*) em `semanal/` e `mensal/` e restore-test semanal agendado.
