# Asset 1: Melhores Práticas de Redes e Isolamento de Tráfego SaaS

Este guia técnico descreve como arquitetar e implementar um ambiente de **Cloud Workstations** altamente seguro no Google Cloud Platform (GCP). O foco principal deste guia é **permitir o acesso a serviços SaaS na nuvem (GitHub.com e Bitbucket.org) para fins corporativos, enquanto impede estritamente que os usuários finais compartilhem ou vazem propriedade intelectual para repositórios ou contas pessoais.**

---

## 1. Visão Geral da Arquitetura Segura

Para resolver o desafio técnico onde domínios como `github.com` e `bitbucket.org` compartilham os mesmos blocos de IPs públicos para uso pessoal e corporativo, propomos uma arquitetura baseada em **defesa em profundidade**.

```mermaid
graph TD
    subgraph Container_Workstation ["Ambiente do Desenvolvedor (Workstation)"]
        Git["Comando Git (HTTPS)"]
        CA["Certificado CA do Proxy instalado"]
    end

    subgraph VPC_GCP ["VPC Privada do Cliente"]
        FW["Firewall GCP: Bloqueia Porta 22 (SSH)"]
        SWP["Cloud Secure Web Proxy (SWP)"]
        TLS["TLS Inspection (Decriptografia e Inspeção)"]
    end

    subgraph Internet_SaaS ["Serviços Cloud SaaS"]
        NAT["Cloud NAT (IPs Públicos Estáticos Fixos)"]
        GitHubCorp["GitHub Corp: github.com/sua-empresa/*"]
        BitbucketCorp["Bitbucket Corp: bitbucket.org/sua-empresa/*"]
        PersonalSaaS["SaaS Pessoal (Push BLOQUEADO)"]
    end

    Git -->|1. Tráfego HTTPS na Porta 443| FW
    FW -->|2. Encaminha para Proxy| SWP
    SWP -->|3. Inspeção de Path/Verbo HTTP| TLS
    TLS -->|4. Se Org Corporativa| NAT
    TLS -.->|4. Se Org Pessoal - HTTP 403| PersonalSaaS
    NAT -->|5. IP Whitelisted| GitHubCorp
    NAT -->|5. IP Whitelisted| BitbucketCorp
```

---

## 2. Elementos Fundamentais de Rede e Isolamento

### 2.1 Rede VPC 100% Privada (Sem IPs Públicos)
As VMs subjacentes às Cloud Workstations devem ser provisionadas sem endereços IP públicos externos (`--disable-public-ip-addresses` na configuração da workstation). Todo o tráfego de gerenciamento de infraestrutura deve ocorrer através de rotas privadas gerenciadas pela rede do Google, protegidas pelo **Identity-Aware Proxy (IAP)**.

### 2.2 Private Google Access (Acesso Privado)
Habilite o **Private Google Access** na subrede da VPC. Sem IP público e sem internet direta, as workstations dependem dessa funcionalidade para baixar imagens base do Artifact Registry, registrar métricas no Cloud Logging e comunicar-se internamente com as APIs do GCP utilizando rotas privadas de alto desempenho.

---

## 3. Estratégia de Restrição de Escrita SaaS (GitHub & Bitbucket)

Para restringir o push de código a namespaces pessoais mantendo o acesso corporativo, são empregadas três estratégias conjuntas de rede:

### 3.1 Cloud Secure Web Proxy (SWP) com TLS Inspection
Um firewall L3/L4 comum de mercado não consegue filtrar caminhos de URL HTTPS. Para o GCP, a melhor prática para filtragem de camada de aplicação (L7) é o **Cloud Secure Web Proxy (SWP)** integrado ao **TLS Inspection**.

1. **Decriptografia Segura**: O SWP intercepta conexões HTTPS de saída destinadas ao GitHub e Bitbucket e as decriptografa temporariamente utilizando uma chave de CA corporativa gerada e controlada pelo cliente (configurada via GCP Certificate Manager / CA Service). O certificado correspondente é instalado como confiável no container da workstation.
2. **Inspeção de URL Path**: Com o tráfego aberto, o proxy analisa a URL exata do repositório:
   - **Permitido**: `https://github.com/sua-empresa/*` (GET e POST)
   - **Permitido**: `https://bitbucket.org/sua-empresa/*` (GET e POST)
   - **Bloqueado**: `https://github.com/perfil-pessoal/*` (Qualquer POST/push)
3. **Bloqueio Seletivo por Verbos HTTP**: É possível configurar o SWP para permitir comandos de leitura (`GET` para `git clone/pull`) para repositórios públicos externos (facilitando download de pacotes públicos), mas **bloquear estritamente qualquer requisição de escrita** (`POST`, `PUT`, `PATCH`) para destinos fora da organização corporativa homologada.

### 3.2 Bloqueio de SSH (Porta 22) de Saída
O protocolo Git sobre SSH (`git@github.com:...`) trafega por meio de um stream binário criptografado fim a fim sobre a porta TCP 22. Como o SSH não possui o conceito de cabeçalhos ou caminhos de URL HTTP, ele contorna completamente as regras de inspeção do Secure Web Proxy.
* **Melhor Prática**: Implementar uma regra de Firewall VPC com ação `DENY` e direção `EGRESS` para impedir qualquer tráfego de saída destinado à porta `22` na subrede das workstations.
* **Funcionamento**: Isso força o desenvolvedor e as ferramentas Git do container a utilizarem obrigatoriamente o transporte HTTPS na porta `443`, que passa pelo filtro do proxy L7.

### 3.3 Cloud NAT com IPs Estáticos (IP Whitelisting)
Associe endereços IP externos públicos **estáticos** (reservados previamente no GCP Compute Engine) ao gateway **Cloud NAT** da VPC, em vez de utilizar alocação dinâmica automática de IPs.
* **Benefício**: Registre esses IPs estáticos da empresa nas regras de proteção de IP (IP Allow List) do GitHub Enterprise Cloud ou Bitbucket Cloud da organização.
* **Resultado**: O acesso ao SaaS corporativo só será aceito quando originado das workstations seguras (que saem pelo NAT com os IPs cadastrados). Se um desenvolvedor tentar acessar repositórios corporativos de sua máquina pessoal, o SaaS rejeitará a conexão por estar fora da faixa de IPs permitida.

---

## 4. Práticas de Implementação Recomendadas

Para a construção de sua primeira infraestrutura de rede segura com o objetivo de proteger o acesso ao GitHub/Bitbucket SaaS e evitar vazamento de dados, recomendamos que sua equipe de plataforma siga as seguintes etapas de implementação:

1. **Provisionar a VPC Privada** e habilitar o Private Google Access na subrede principal.
2. **Configurar o Cloud Secure Web Proxy (SWP)** com TLS Inspection integrado ao Certificate Manager para interceptar e auditar o tráfego HTTPS direcionado a `github.com` e `bitbucket.org`.
3. **Criar políticas de segurança L7 no SWP** que bloqueiem métodos POST/PUT/PATCH para caminhos fora do domínio corporativo (ex: permitindo apenas `github.com/sua-empresa/*` e `bitbucket.org/sua-empresa/*`).
4. **Implementar a Regra de Bloqueio SSH (Porta 22)** desde o primeiro dia de validação do ambiente para forçar o uso do protocolo HTTPS, permitindo a inspeção de tráfego.
5. **Associar IPs públicos estáticos ao Cloud NAT** e registrá-los na allowlist de IP das organizações do GitHub/Bitbucket corporativas para restringir o acesso apenas a conexões originadas de workstations autorizadas.
