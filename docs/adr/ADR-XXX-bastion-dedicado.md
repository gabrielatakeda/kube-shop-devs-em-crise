# ADR-XXX: Bastion dedicado como único ponto de entrada SSH

> Renumerar seguindo a sequência dos ADRs da Entrega 1.

- **Status:** aceita
- **Data:** 18/11/2026
- **Substitui:** versão anterior do projeto em que a VM da aplicação também era o bastion (registrar em `docs/errata.md` se a Entrega 1 previa outra solução)

## Contexto

A arquitetura implantada tem duas VMs exigidas pelo escopo do KubeShop: a da aplicação (sub-rede pública, serve a loja em HTTPS) e a do MongoDB (sub-rede privada). A Entrega 2 exige um recurso de acesso com IP público (R6), SSH restrito a um CIDR (R7) e a demonstração D3 (SSH ao bastion e à instância privada via bastion).

Na primeira versão, a VM da aplicação acumulava as funções de servidor web e de bastion. Assim, uma falha explorável na aplicação (exposta à internet nas portas 80/443) daria ao atacante um host que é, ao mesmo tempo, o ponto de salto administrativo para a VM do banco.

## Decisão (Y-statement)

No contexto do acesso administrativo às VMs do KubeShop, diante da necessidade de separar a superfície exposta da aplicação do caminho de administração, decidimos criar **uma VM bastion dedicada (t3.micro, sub-rede pública, IP fixo; t3.nano não é elegível no plano Free Tier da conta)**, que passa a ser **o único host que aceita SSH da internet** (apenas dos CIDRs autorizados), com a VM da aplicação e a VM do banco aceitando SSH **somente a partir do SG do bastion**. Descartamos manter a VM da aplicação como bastion, para atingir a separação de funções e reduzir o raio de impacto de um comprometimento da aplicação, **aceitando que** isso acrescenta uma VM e um IP público ao custo mensal (cerca de US$ 11,90/mês em operação contínua na us-east-2, somando VM t3.micro, IP público e disco de 8 GB; poucos centavos no período de testes; confirmar na calculadora oficial) e mais um host para manter atualizado.

## Consequências

- **Rede:** novo SG `sg-bastion` (entrada 22 dos `ssh_allowed_cidrs`; saída 22 para `sg-app` e `sg-db`, 80/443 para atualizações). `sg-app` deixou de aceitar SSH da internet. `sg-db` aceita SSH só do bastion.
- **Bastion mínimo:** sem role IAM, sem Docker, sem dados, sem chaves privadas gravadas. É o único host com `AllowTcpForwarding yes`; app e banco têm `AllowTcpForwarding no`.
- **Pipeline:** a regra SSH temporária do runner é aberta no SG do bastion. O Ansible acessa app e banco pelos IPs privados, saltando pelo bastion.
- **Verificação:** a pipeline confirma que a porta 22 da VM da aplicação **não** responde pela internet.
- **D3:** `ssh ubuntu@<bastion>` e `ssh -J ubuntu@<bastion> ubuntu@<ip-privado>` para app e banco (comandos no output `ssh_commands`).
- **Risco residual:** comprometimento da chave privada do grupo. Mitigado pelo CIDR restrito, por S1 e pela rotação da chave em caso de vazamento.
- **Evolução (proposta de HA):** substituir o bastion por AWS Systems Manager Session Manager, eliminando a porta 22 de entrada.
