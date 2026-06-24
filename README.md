# Guia de Implantação e Melhores Práticas: Cloud Workstations de Alta Segurança

Este repositório contém as diretrizes arquiteturais, o modelo referencial de rede e a configuração do container de desenvolvimento para a implantação de um ambiente de desenvolvimento altamente seguro utilizando o **Google Cloud Workstations** na infraestrutura de sua organização.

Nossa arquitetura e diretrizes focam no atendimento a um requisito de segurança crítico do ambiente corporativo moderno: **permitir que os engenheiros e desenvolvedores utilizem e clonem códigos de serviços SaaS públicos (como GitHub e Bitbucket) de escopo estritamente corporativo, ao mesmo tempo em que bloqueia e previne vazamentos ou pushes de código para repositórios ou contas pessoais.**

Todas as melhores práticas, decisões de design de rede e requisitos operacionais estão detalhados de forma **trilíngue (Português, Inglês e Espanhol)** no diretório `docs/`.

---

## 🛠️ 1. Estrutura de Arquivos do Repositório

O repositório está organizado de forma modular e limpa para facilitar o processo de auditoria e compilação:

```text
cloud-workstations-custom/
├── Dockerfile               # Definição imutável da imagem customizada (Code OSS + Chrome + Git Hardening + Proxy)
├── README.md                # Este guia principal com roteiros de implantação e homologação técnica
├── config/
│   └── AGENTS.md            # Cartilha local de diretrizes de desenvolvimento seguro exibida no workspace
├── scripts/
│   └── 210_setup_corporate_git.sh # Script de boot da workstation para autocura e persistência de políticas locais
└── docs/                    # Documentação técnica detalhada e trilíngue
    ├── security_networking_best_practices.md         # Asset 1 (PT): Melhores Práticas de Redes
    ├── security_networking_best_practices_en.md      # Asset 1 (EN)
    ├── security_networking_best_practices_es.md      # Asset 1 (ES)
    ├── maintenance_access_control_best_practices.md  # Asset 2 (PT): Acesso e Requisitos de Imagem
    ├── maintenance_access_control_best_practices_en.md # Asset 2 (EN)
    └── maintenance_access_control_best_practices_es.md # Asset 2 (ES)
```

---

## 📐 2. Modelo Referencial de Arquitetura de Segurança de Rede

No **Asset 1 (Melhores Práticas de Redes)**, detalhamos como a arquitetura baseada em **Secure Web Proxy (SWP) com TLS Inspection** opera para oferecer controles de DLP na camada de aplicação (L7) diretamente sobre o tráfego destinado aos serviços de SaaS públicos (GitHub e Bitbucket).

Esta arquitetura baseia-se em quatro pilares integrados que atuam em conjunto para garantir o acesso corporativo seguro e evitar o vazamento de dados:
* **Cloud Secure Web Proxy (SWP) com TLS Inspection**: Intercepta e decodifica conexões HTTPS de saída destinadas aos domínios SaaS (`github.com` e `bitbucket.org`). Ele inspeciona o caminho exato da URL e os verbos HTTP, autorizando ações corporativas (como GET e POST para `github.com/sua-empresa/*`) enquanto bloqueia escritas/pushes para contas e repositórios pessoais.
* **BeyondCorp Enterprise (BCE) DLP**: Aplica políticas de segurança na camada de navegação (browser/Web IDE) para bloquear ações físicas de vazamento, como copiar e colar (clipboard) entre a máquina local e a workstation, downloads de código para o computador físico e impressões de tela.
* **Regra de Firewall VPC (Egress DENY na Porta 22)**: Bloqueia o protocolo Git via SSH externo. Isso força todo o tráfego do Git a trafegar obrigatoriamente via HTTPS, passando diretamente pela inspeção L7 do proxy.
* **Cloud NAT com IPs Públicos Estáticos Fixos**: Centraliza e unifica todo o tráfego de saída das workstations sob IPs conhecidos, permitindo o cadastro desses IPs na lista de liberação de IP (IP Allow List) das organizações SaaS do GitHub/Bitbucket corporativas do cliente, restringindo o acesso exclusivamente ao perímetro das workstations autorizadas.

---

## 🐳 3. Requisitos para Imagens Customizadas

No **Asset 2 (Controle de Acesso e Manutenção)**, detalhamos nas três línguas as regras obrigatórias e recomendadas para a consolidação de imagens de desenvolvimento customizadas.

### Requisitos Indispensáveis (Hard Requirements):
1. **Herança de Imagem Base Oficial**: Todo Dockerfile deve herdar de imagens base oficiais homologadas do Google (ex: `FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest`), garantindo os proxies gRPC de rede do plano de controle.
2. **Contexto de Execução Não-Root**: Configurar obrigatoriamente `USER user` (UID 1000) ao final da compilação da imagem. Isso impede que os desenvolvedores desativem as regras locais de Git e proxy do sistema de dentro do container.
3. **Instalação e Gestão de ca-certificates**: Indispensável para suportar cadeias de certificados corporativos privados, necessárias para a decriptografia TLS no Secure Web Proxy.
4. **Git Hardening com core.hooksPath**: Uso da propriedade global `core.hooksPath` em `/etc/gitconfig` apontando para `/etc/git/hooks/`. Como o arquivo de configuração e a pasta de ganchos pertencem ao `root` (e o usuário final não possui privilégios root), o gancho de validação `pre-push` é executado de forma mandatória e imutável para **todos** os repositórios locais do usuário, novos ou pré-existentes.

### Estrutura Base Recomendada no Container:
* `/etc/security/`: Pasta administrativa para armazenar diretrizes locais e políticas de conformidade (ex: `AGENTS.md`).
* `/etc/workstation-startup.d/`: Pasta padrão de scripts executados de forma automática como `root` no boot da máquina após a montagem do disco persistente `/home/user`. Útil para autocura de links e atualização dinâmica de certificados.
* `/etc/git/hooks/`: Diretório global para ganchos Git imutáveis do sistema.
* `/usr/local/share/ca-certificates/`: Diretório para depósito de certificados corporativos privados `.crt`.

---

## 🚀 4. Guia de Provisionamento e Criação Segura (GCP Console / gcloud)

Abaixo estão as etapas recomendadas para que sua equipe de plataforma e engenharia de segurança provisione as workstations e a infraestrutura segura de forma estruturada:

### Etapa 1: Provisionar a Rede e Regras de Segurança
1. Crie uma **VPC Privada** com subredes configuradas com o **Acesso Privado do Google (Private Google Access)** ativado.
2. Defina uma **Regra de Firewall de Saída (Egress)** bloqueando a porta TCP `22` (SSH) com destino a domínios externos de código SaaS (como `github.com` e `bitbucket.org`).
3. Instancie um **Cloud Router** e um **Cloud NAT** associado, configurando um conjunto de **IPs externos estáticos pré-alocados**. Esses IPs serão cadastrados na lista de controle de acesso (IP Allow List) do seu GitHub/Bitbucket Enterprise corporativo.

### Etapa 2: Configurar o Secure Web Proxy (SWP) com TLS Inspection
1. Aloque um certificado de CA corporativa confiável no **GCP Certificate Manager** ou **CA Service**.
2. Crie a instância do **Secure Web Proxy (SWP)** no GCP, associando-a à subrede das workstations.
3. Configure regras de política de URL L7 para decriptografia HTTPS. Defina as regras de gravação (`POST`/`PUT`/`PATCH`) para autorizar conexões estritamente destinadas à organização corporativa cadastrada (ex: `github.com/sua-empresa/*`).

### Etapa 3: Compilar e Enviar a Imagem Customizada
1. Compile a imagem Docker baseada no `Dockerfile` fornecido na raiz deste repositório utilizando o **Cloud Build**:
   ```bash
   gcloud builds submit --tag us-central1-docker.pkg.dev/[SEU_PROJETO_GCP]/[REGISTRY_NAME]/secure-code-oss:latest .
   ```
2. A imagem compilada e endurecida de segurança (hardened) será salva no **Artifact Registry** privado de sua organização.

### Etapa 4: Instanciar e Endurecer a Configuração da Workstation
1. No console do GCP, crie o **Workstation Cluster** apontando para a sua subrede privada.
2. Crie a **Workstation Configuration**:
   - Associe a imagem Docker customizada armazenada no Artifact Registry.
   - **Variável de Ambiente Recomendada**: Adicione a variável `ALLOWED_ORG` com o nome da sua organização SaaS corporativa. O hook global `pre-push` lerá essa variável de forma dinâmica.
   - **Desativação Nativa de Sudo (Essencial)**: Defina a variável de ambiente nativa do GCP `CLOUD_WORKSTATIONS_CONFIG_DISABLE_SUDO = true`. Isso faz com que o Google remova todas as capacidades e direitos de `sudo/root` do usuário de desenvolvimento de forma nativa e imutável pelo plano de controle.
   - **Segurança de Acesso e DLP**: Habilite as políticas do **BeyondCorp Enterprise** na configuração para aplicar o controle de prevenção de perda de dados (bloqueio de cópia, colagem, impressão e download) diretamente na sessão web da IDE.
   - Configure o ciclo de vida: **Idle Timeout** de 30 minutos e **Auto-stop** diário de 12 horas.
   - Aplique a criptografia de discos usando chaves gerenciadas pelo cliente (**CMEK**) via Cloud KMS.
3. Instancie e atribua as estações de trabalho de forma individual aos desenvolvedores, concedendo as permissões do IAM de criador (`roles/workstations.user`) em nível de recurso e protegendo o acesso de rede via **Identity-Aware Proxy (IAP)** combinado com regras de **Context-Aware Access** (acesso restrito apenas a dispositivos homologados da corporação).

---

## 🧪 5. Roteiro de Homologação e Testes Técnicos

Abaixo está o roteiro de testes recomendado para demonstrar e comprovar o funcionamento de cada camada de segurança aplicada no ambiente:

### Teste A: Verificação de Aplicações Corporativas (Chrome)
1. No console do GCP, inicie a workstation criada e abra o **Code OSS** no navegador.
2. Abra o terminal integrado do Code OSS e execute:
   ```bash
   google-chrome --version
   ```
   *Resultado esperado:* O terminal deve retornar a versão instalada estável do Google Chrome, comprovando que a imagem customizada foi montada com sucesso.

### Teste B: Imutabilidade e Autocura do Documento de Diretrizes
1. No terminal do Code OSS, verifique que o arquivo `AGENTS.md` está visível na raiz do workspace do usuário (`/home/user/AGENTS.md`).
2. Tente editar e salvar o arquivo diretamente no editor Code OSS.
   - *Resultado esperado:* O editor exibirá um erro de permissão bloqueando a gravação (`Permission Denied`), provando que as diretrizes são de posse do `root` e não podem ser adulteradas pelo desenvolvedor comum.
3. No terminal, force a exclusão do arquivo:
   ```bash
   rm /home/user/AGENTS.md
   ```
4. Reinicie a workstation (pare e inicie novamente pelo console do GCP ou pelo botão da IDE).
   - *Resultado esperado:* O arquivo `AGENTS.md` reaparece intacto! Nosso script de boot `/etc/workstation-startup.d/210_setup_corporate_git.sh` detectou a ausência e recriou o link simbólico automaticamente.

### Teste C: Bloqueio do Protocolo SSH (Porta 22) de Rede
1. No terminal do Code OSS, tente estabelecer uma conexão SSH de saída direta com o GitHub ou Bitbucket:
   ```bash
   ssh -T git@github.com
   ```
   - *Resultado esperado:* A conexão deve falhar por timeout ou ser recusada imediatamente. Isso prova que a regra de firewall de egress da VPC bloqueou com sucesso a porta `22`, impedindo desvios criptografados que contornam a inspeção de tráfego.

### Teste D: Clonagem de Repositórios HTTPS Permitidos
1. No terminal, tente realizar o clone de um repositório corporativo que corresponda à organização permitida:
   ```bash
   git clone https://github.com/sua-empresa/projeto-teste.git
   ```
   - *Resultado esperado:* Conexão autorizada e clone executado com sucesso (desde que as credenciais e acessos estejam corretos no SaaS).

### Teste E: Bloqueio Total de Push para Contas Pessoais (DLP Ativo)
Este teste valida a barreira de prevenção de vazamento de dados em três frentes de controle integradas:

1. **Tentativa de Push por Repositório Não Autorizado (Filtro local imutável do container)**:
   - Crie ou use qualquer repositório local e tente associá-lo a um destino pessoal do desenvolvedor fora do escopo corporativo:
     ```bash
     git remote set-url origin https://github.com/perfil-pessoal/repositorio-vazado.git
     git push origin main
     ```
   - *Resultado esperado:* O comando será cancelado imediatamente pelo hook de segurança local `pre-push` global da máquina (mesmo que o usuário crie um repositório novo ou tente excluir pastas locais do git), retornando o seguinte aviso:
     `🚨 ERRO: TENTATIVA DE EXFILTRAÇÃO DETECTADA 🚨`
     `Neste ambiente, pushes são autorizados apenas para a org: sua-empresa`

2. **Tentativa de Escrita/Push Não Autorizada de Rede (Regras do Secure Web Proxy - L7)**:
   - No setup produtivo real com SWP e TLS Inspection habilitados, qualquer chamada HTTPS contendo rotas ou URLs destinadas a namespaces não-corporativos para operações de gravação (`POST`) é barrada na camada de rede pelo proxy, retornando um erro de rede `HTTP 403 Forbidden`.

3. **Bloqueio de Sudo pelo Usuário**:
   - Tente desativar as travas do Git editando `/etc/gitconfig` ou executando comandos priviligiados:
     ```bash
     sudo -i
     ```
   - *Resultado esperado:* O comando falhará com um aviso informando que o usuário `user` não pertence ao grupo de sudoers. Graças à flag `CLOUD_WORKSTATIONS_CONFIG_DISABLE_SUDO=true`, o usuário final é um desenvolvedor comum sem privilégios de bypass.

---

## 📈 6. Resumo Técnico das Camadas de Defesa (Defense in Depth)

| Camada de Controle | Tecnologia GCP / Mecanismo | Proteção Efetiva contra Ameaças |
| :--- | :--- | :--- |
| **1. Rede (Egress Control)** | VPC Firewalls (Bloqueio Porta 22) | Impede desvios binários criptografados que usam SSH para vazar dados. Força tráfego de Git para HTTPS. |
| **2. Proxy Granular (L7)** | Secure Web Proxy + TLS Inspection | Analisa caminhos de URL de saída corporativos vs. pessoais, bloqueando escritas fora do domínio corporativo. |
| **3. Whitelisting de IP** | Cloud NAT com IPs Estáticos Fixos | Permite bloquear acessos externos às contas corporativas de GitHub/Bitbucket. Somente IPs cadastrados das workstations acessam o SaaS. |
| **4. Endurecimento Local (DLP)** | Global `/etc/gitconfig` + `core.hooksPath` global imutável | Oferece validação redundante e independente direto no container para todos os repositórios (novos ou existentes), sem risco de bypass. |
| **5. Sem Privilégios Root** | `CLOUD_WORKSTATIONS_CONFIG_DISABLE_SUDO=true` | Bloqueia de forma nativa e imutável do lado do GCP qualquer tentativa do usuário final de desativar os proxies do container ou alterar ganchos de segurança. |
| **6. Prevenção de Perda de Dados** | BeyondCorp Enterprise DLP | Bloqueia ações de cópia, colagem (clipboard), downloads de arquivos e impressões de tela da IDE para a máquina física. |
| **7. Controle de Contexto** | Identity-Aware Proxy + Context-Aware Access | Restringe a conexão com o ambiente web da IDE exclusivamente para dispositivos corporativos gerenciados e confiáveis. |
| **8. Isolamento de Identidade** | GitHub EMU e Atlassian Guard | Alinha identidades com o Provedor de Identidade corporativo (IdP) e desabilita a criação de repositórios pessoais na mesma conta. |
| **9. Políticas de Governança** | Idle Timeout de 30min + Auto-stop diário | Mitiga riscos de sessões órfãs ou expostas e reduz drasticamente o consumo e os custos de infraestrutura do GCP. |

Se sua equipe de arquitetura ou segurança possuir qualquer dúvida ou necessidade de customização nos templates fornecidos, nossa equipe técnica está totalmente à disposição para colaborar! 🚀
