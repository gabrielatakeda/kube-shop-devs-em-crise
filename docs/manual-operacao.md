# Manual de operação — KubeShop

> Para a equipe da Zibiska Korp (escopo §10). Todas as rotinas rodam em **GitHub → Actions → (workflow) → Run workflow**. Nenhuma exige acesso ao console da AWS nem senha.

## Rotinas do dia a dia

| Quero… | Workflow | Parâmetros | Resultado esperado |
|---|---|---|---|
| Ver se a loja está saudável | `ops` | `operation = health` | Execução verde; o log mostra os 4 contêineres `(healthy)`, `readiness: {"ready":true,"database":true}` e a versão |
| Ver os logs | `ops` | `operation = logs`, `service = all` (ou um serviço), `log_lines = 200` | Artefato `ops-logs-*` com um arquivo por serviço, mais o log do backup |
| Reiniciar um serviço | `ops` | `operation = restart`, `service = api` (por exemplo) | Serviço reiniciado e saudável; pedidos preservados |
| Fazer backup agora | `ops` | `operation = backup` | Resumo com `s3://…/diario/kubeshop-<env>-<data>.archive.gz`, tamanho, `aws:kms` e data de expiração |
| Testar a restauração | `ops` | `operation = restore-test` | Resumo com coleções e quantidade de pedidos restaurados num MongoDB temporário. **O ambiente principal não é tocado** |
| Ver as mudanças antes de aplicar | `infra-deploy` | `action = plan` + parâmetros | Resumo com o plano do Terraform (`+` cria, `~` altera no lugar, `-/+` substitui, `-` destrói) |
| Criar ou atualizar o ambiente | `infra-deploy` | `action = apply`, `docker_tag = 1.0.1`, etc. | Terraform → Ansible → verificação externa; o resumo mostra URL, versão e "SSH direto na VM da aplicação: bloqueado" |
| Voltar para a versão anterior | `infra-deploy` | `action = apply`, `docker_tag = <versão anterior>` | `/api/info` volta a mostrar a versão anterior; dados preservados |
| Atualizar o sistema operacional | `infra-deploy` | `action = apply`, `update_os = true` | VMs atualizadas uma por vez (com reinício, se necessário) |

## Rotinas que removem dados ou recursos (exigem confirmação digitada)

| Quero… | Workflow | Parâmetros | O que acontece |
|---|---|---|---|
| Limpar os pedidos para uma nova demonstração | `ops` | `operation = reset-demo`, `confirm = LIMPAR-<env>` | **Backup automático antes**, depois apaga a coleção `orders`. O resumo informa o backup feito, para desfazer se precisar |
| Encerrar o ambiente (fim do evento ou da sessão de testes) | `infra-destroy` | `confirm = DESTRUIR-<env>` | Remove **tudo** do ambiente: VMs, NAT, IPs, discos, **bucket de backup com as cópias** e senhas. Depois confere na AWS o que sobrou e gera `inventario-pos-destroy.md` |

**Destino dos dados no destroy:** os pedidos e os backups são apagados. Se for preciso guardar, rode `ops → backup` e baixe o arquivo do S3 **antes**.

**O que continua gerando cobrança depois do destroy:**
- chave KMS em exclusão pendente (7 dias);
- bucket do Terraform state (alguns KB);
- alerta de orçamento e role da pipeline, sem custo.

## Acesso administrativo (SSH)

Só pelo bastion, só da rede cadastrada em `SSH_ALLOWED_CIDR` e só com a chave do grupo.

```bash
ssh-add ~/.ssh/kubeshop-grupo
```

```bash
ssh ubuntu@<IP_BASTION>
```

```bash
ssh -J ubuntu@<IP_BASTION> ubuntu@<IP_PRIVADO_APP>
```

```bash
ssh -J ubuntu@<IP_BASTION> ubuntu@<IP_PRIVADO_DB>
```

Os IPs e comandos prontos aparecem no output `ssh_commands`, no resumo da execução do `infra-deploy`.

## Diagnóstico de falhas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `infra-deploy` falha em "Valida parâmetros" | Variável ou secret não cadastrado, ou parâmetro com formato inválido | Ler a mensagem `::error::` e cadastrar a variável indicada |
| Falha em `configure-aws-credentials` | Secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` errados ou ausentes | Conferir com `terraform output aws_access_key_id` e `terraform output -raw aws_secret_access_key` no `bootstrap` |
| `terraform plan` falha com *state lock* | Outra execução no mesmo ambiente (ou uma interrompida) | Esperar; se travou, apagar o arquivo `.tflock` no bucket do state |
| Ansible: `UNREACHABLE` no bastion | Regra SSH temporária não criada ou VM ainda iniciando | Reexecutar; o playbook espera até 5 min pelo SSH |
| Ansible: falha ao baixar a imagem | Pacote do GHCR privado ou `docker_tag` inexistente | Tornar o pacote público; conferir a tag publicada pelo `app-ci` |
| `health` mostra `api` *unhealthy* e `readiness.database = false` | MongoDB parado ou inacessível | `ops → logs` (`service = mongodb`), depois `ops → restart` (`service = mongodb`) |
| Navegador acusa certificado inválido | Certificado autoassinado (esperado) | Aceitar o aviso; com domínio próprio, usar Let's Encrypt/ACM |
| Meu SSH parou de funcionar | Mudou o IP da rede | Atualizar `SSH_ALLOWED_CIDR` (ou o parâmetro `ssh_allowed_cidr`) e rodar `infra-deploy` |
| `infra-destroy` termina com "RESTANTE" | Recurso criado fora do Terraform ou exclusão ainda em andamento (NAT leva minutos) | Rodar de novo após alguns minutos; o inventário diz o que sobrou |

## Preparação para uma demonstração

1. `infra-deploy` com `action = apply` (cerca de 10–15 min com o NAT), **antes** do horário.
2. `ops → health`.
3. Se quiser lista de pedidos limpa: `ops → reset-demo`.
4. Abrir `https://<IP_APP>` em outro dispositivo, aceitar o certificado e fazer um pedido.
5. Ao terminar: `infra-destroy`.
