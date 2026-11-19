# Análise da demanda — KubeShop (Zibiska Korp)

> Documento de demanda: **Escopo KubeShop v1.2 (11/11/2026)**, em `escopo.pdf`. Este arquivo é a base da seção "análise da demanda e decisões de arquitetura" do PDF da PM-04 e da validação dos requisitos.

## 1. O que o cliente pede

A Zibiska Korp quer lançar o próprio marketplace usando o **KubeShop**: frontend React servido por Nginx, API Node.js/Express e MongoDB autenticado. Pedidos e produtos são fictícios, não há login nem pagamento. O código e um CI/CD da aplicação existem; falta **quem implante e administre a infraestrutura por pipelines**, com aplicação e banco em **servidores distintos**.

## 2. Componentes e dependências identificados

| Componente | Imagem / origem | Depende de | Porta | Observação do repositório |
|---|---|---|---|---|
| Frontend | `kubeshop-frontend` (Nginx 1.28 + build Vite) | API (proxy de `/api`) | 8080 | Usuário não-root, FS somente leitura, CSP |
| API | `kubeshop-api` (Node 24) | MongoDB | 3000 | `/api/health/ready` testa o banco; senha via `MONGO_PASSWORD_FILE`; host via `MONGO_HOST` |
| MongoDB | `mongo:8.0.17` | Disco persistente | 27017 | `init.js` cria o usuário da aplicação (`readWrite` em `kubeshop`) |
| Proxy TLS *(adicionado)* | `nginx:1.28.0-alpine` | Frontend | 443/80 | HTTPS sem alterar a imagem do frontend |

O repositório não trazia pipeline de CI/CD (o escopo cita um CI existente do cliente). Criamos o `app-ci.yml` para representar esse fluxo e documentamos o ponto de integração (abaixo).

## 3. Decisões e justificativas

| Decisão | Escolha | Por que atende a demanda |
|---|---|---|
| Provedor | **AWS** | Provedor livre; Terraform maduro; integração com GitHub Actions; serviços gerenciados de NAT, KMS, SSM e S3; o grupo já tem a conta |
| Região | **us-east-2 (Ohio)** | Preço menor que São Paulo para NAT, EC2 e IPv4; o público da demonstração não é sensível a latência de algumas dezenas de ms |
| Servidores | **3 VMs**: bastion (t3.micro), aplicação (t3.micro), MongoDB (t3.micro) | REQ-01/02 pedem no mínimo 2 com banco exclusivo. O bastion é o recurso adicional, **justificado** pela separação do acesso administrativo (ADR do bastion) |
| Rede | VPC com sub-rede pública (bastion, app, NAT) e privada (banco); NAT gerenciado | REQ-03: banco só pela rede privada; o banco sem IP público ainda baixa atualizações e envia backup |
| Acessos | SG do banco aceita 27017 só da app; SSH só do bastion; bastion só dos CIDRs do grupo; SSH só por chave | REQ-02/04 |
| Persistência | Disco EBS de dados dedicado ao MongoDB + backup diário no S3 + restore-test | REQ-05 e ACE-05/07: dados preservados em reinício, atualização e troca de tipo de instância |
| Execução nas VMs | Docker Compose por VM (gerado pelo Ansible) | Reaproveita o Compose validado do projeto, só dividido em dois hosts |
| Segredos | SSM Parameter Store (SecureString com CMK) + GitHub Secrets (inclusive a access key da pipeline) | REQ-04: nada no repositório nem nos logs |
| Automação | GitHub Actions: `app-ci`, `security`, `infra-deploy`, `ops`, `infra-destroy` | §9 do escopo: validar, provisionar, atualizar, manter, proteger e desativar |
| Custo | ≈ US$ 69/mês contínuo; ≈ US$ 3,75 no período de uso | ACE-09, `docs/custos/estimativas.md` |

## 4. Requisitos do escopo → infraestrutura entregue

| Requisito | Como é atendido | Arquivo |
|---|---|---|
| REQ-01 Servidores | 2 VMs de função (app e banco) + bastion | `infra/compute.tf` |
| REQ-02 Banco isolado | MongoDB só na VM do banco; sub-rede privada; sem IP público; 27017 publicado só no IP privado | `infra/compute.tf`, `security.tf`, `ansible/roles/kubeshop_db` |
| REQ-03 Rede privada | API → `MONGO_HOST = <IP privado>`; SG do banco referencia o SG da app | `infra/security.tf`, `ansible/roles/kubeshop_app` |
| REQ-04 Acessos | Bastion + CIDR; S1; segredos no SSM; `no_log`; usuário IAM da pipeline com escopo mínimo | `infra/security.tf`, `ssh_hardening`, workflows |
| REQ-05 Persistência | EBS de dados + `restart: unless-stopped` + backup e restauração | `infra/compute.tf`, `ansible/roles/backup`, `ops.yml` |
| §5 Adaptação para servidores separados | Compose dividido em `kubeshop-app` e `kubeshop-db`; endereço privado; ordem de inicialização garantida por healthchecks e `depends_on` | `ansible/roles/*/templates/compose.yaml.j2` |
| §7 CI/CD da aplicação | `app-ci.yml`: testes, build, Trivy, publicação no GHCR com versão. **Integração:** a imagem `ghcr.io/<owner>/kubeshop-{api,frontend}:<versão>` é o destino; a infra consome pelo parâmetro `docker_tag` | `.github/workflows/app-ci.yml` |
| §8 IaC e state | Terraform versionado; state no S3 (versionado, criptografado, lock); recuperação pelo versionamento | `infra/`, `bootstrap/` |
| §9 Operações | Validar e planejar (`security` + `plan`), provisionar (`apply` + Ansible), atualizar (`docker_tag`, `update_os`), manter (`ops health/logs/restart`), proteger (`ops backup/restore-test`), desativar (`infra-destroy`) | `.github/workflows/` |
| §10 Operação pelo cliente | Manual com parâmetros, resultados esperados e falhas comuns; ações destrutivas separadas e com confirmação digitada | `docs/manual-operacao.md` |

## 5. Parâmetros da pipeline (PM-04) e o que alteram

| Parâmetro | Tipo de mudança | Efeito real |
|---|---|---|
| `environment` | Infra | State e nomes separados por ambiente (`kubeshop-dev-*`) |
| `instance_name` | Infra | Tag `Name` das VMs (`<nome>-bastion/-app/-db`) |
| `app_instance_type` / `db_instance_type` | Infra | Troca do tipo **no lugar** (`~`, a VM para e volta; IP e dados preservados) |
| `docker_image` / `docker_tag` | Configuração | Ansible baixa a nova imagem e recria só os contêineres afetados; `/api/info` mostra a versão |
| `update_os` | Manutenção | `apt dist-upgrade` + reinício se necessário, uma VM por vez |
| `extra_packages` | Manutenção | Instala os pacotes informados |
| `ssh_allowed_cidr` | Infra | Regras de entrada do SG do bastion |

## 6. Critérios de aceite → evidência

Ver `docs/validacao.md`.
