# Guia de Entrega: Configuração de Cloud Workstations Segura

Olá, Sabrina! É um prazer entregar a você a solução completa, revisada e robusta para o setup seguro de **Google Cloud Workstations** do seu cliente, com foco absoluto no projeto `expanded-flame-422613-e4`.

Este repositório foi reformulado para focar em uma das maiores necessidades de conformidade de segurança empresarial moderna: **permitir que os desenvolvedores utilizem e clonem códigos de serviços SaaS públicos (GitHub e Bitbucket) de escopo corporativo, enquanto impede de forma estrita que realizem o push, vazamento ou compartilhamento de propriedade intelectual para contas ou repositórios pessoais.**

Toda a arquitetura proposta e as melhores práticas estão documentadas em detalhes e de forma **trilíngue (Português, Inglês e Espanhol)** na pasta `docs/`.

---

## 🛠️ 1. Estrutura de Arquivos do Repositório

O repositório local está estruturado da seguinte forma:

```text
secure-cloud-workstations/
├── Dockerfile               # Definição imutável da imagem customizada (Code OSS + Chrome + Git Hardening)
├── gcloud_setup.sh          # Script de automação IaC para provisionar VPC, Firewalls, Cloud NAT e Workstations
├── README.md                # Este documento explicativo e roteiro de homologação
├── config/
│   └── AGENTS.md            # Cartilha local de diretrizes de desenvolvimento seguro (exibida no workspace)
├── scripts/
│   └── 210_link_agents.sh   # Script de boot da workstation para autocura e persistência do AGENTS.md
└── docs/                    # Documentações técnicas trilingues detalhadas
    ├── security_networking_best_practices.md         # Asset 1 (PT): Melhores Práticas de Redes
    ├── security_networking_best_practices_en.md      # Asset 1 (EN)
    ├── security_networking_best_practices_es.md      # Asset 1 (ES)
    ├── maintenance_access_control_best_practices.md  # Asset 2 (PT): Acesso e Requisitos de Imagem
    ├── maintenance_access_control_best_practices_en.md # Asset 2 (EN)
    ├── maintenance_access_control_best_practices_es.md # Asset 2 (ES)
    └── meeting_agenda_workstations.md                # Roteiro de Reunião de 1h com o Cliente (PT)
```

---

## 📐 2. Modelo Referencial e Flexibilidade Arquitetural

No **Asset 1 (Melhores Práticas de Redes)**, estruturamos os guias para deixar claro para o seu cliente que a arquitetura apresentada utilizando **Secure Web Proxy (SWP) com TLS Inspection** é uma **ideia de implementação e um modelo referencial de possibilidades**. 

O Google Cloud oferece flexibilidade para que outras abordagens de controle de redes sejam avaliadas e testadas pelo cliente:
* **Secure Web Proxy (SWP) com TLS Inspection (Modelo Avançado)**: Permite controle granular de caminhos de URL (DLP) mesmo em SaaS na nuvem pública.
* **Isolamento Total de Egress (Modelo Fechado)**: Ideal caso o cliente possua servidores de código (GitHub Enterprise Server / Bitbucket Server) hospedados localmente ou em nuvem privada corporativa, dispensando tráfego de saída para a internet.
* **Cloud NAT Puro (Modelo Simplificado)**: Perfeito para fases de prova de conceito (POC) e validação técnica simples, utilizando o controle de IP público estático como principal barreira.

---

## 🐳 3. Imagens Customizadas: Requisitos e Estrutura Base

No **Asset 2 (Controle de Acesso e Manutenção)**, documentamos em detalhes nas três línguas os critérios exigidos pelo Google Cloud para que o cliente consiga construir suas próprias imagens customizadas em conformidade com as regras corporativas.

### Requisitos Indispensáveis (Hard Requirements):
1. **Herança de Imagem Base Oficial**: Deve-se utilizar obrigatoriamente `FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/...` no Dockerfile. Isso garante a presença do agente interno de comunicação do plano de controle do GCP.
2. **Contexto Não-Root ao Final**: Forçar o container a executar como usuário de UID 1000 (`USER user`). Isso impede que o desenvolvedor altere configurações de segurança locais por meio de privilégios de `root`.
3. **Instalação e Gestão de ca-certificates**: Indispensável para suportar cadeias de certificados CA corporativos (necessários para decriptografia em proxies de inspeção de tráfego L7).
4. **Git Hardening e Bloqueio de SSH de Saída**: Configurar o `/etc/gitconfig` global como somente leitura para reescrever chamadas SSH (`git@...`) em HTTPS (`https://...`).

### Estrutura Base Recomendada no Container:
* `/etc/workstation-startup.d/`: Diretório de inicialização para scripts disparados automaticamente como `root` no boot da máquina.
* `/usr/local/share/ca-certificates/`: Diretório padrão do Debian/Ubuntu para depósito de certificados corporativos privados `.crt`.
* `/etc/git/templates/hooks/`: Diretório base para armazenar templates imutáveis de ganchos do Git (como o `pre-push` local).

---

## 🚀 4. Como Executar a Implantação Automatizada (IaC)

Para rodar o script e provisionar o ambiente de homologação no projeto GCP do seu cliente, execute os passos abaixo no terminal local do seu computador:

### Passo 1: Autenticar no Google Cloud
Garanta que seu terminal esteja logado com as credenciais administrativas do projeto do cliente:
```bash
gcloud auth login
```

### Passo 2: Acessar a pasta e dar permissão de execução
```bash
cd /Users/sabrinaguerra/Documents/antigravity/eager-shannon
chmod +x gcloud_setup.sh
```

### Passo 3: Executar o Setup automatizado
```bash
./gcloud_setup.sh
```
*O script é totalmente idempotente. Ele verificará cada recurso antes de criá-lo (redes VPC, subredes, Cloud Router, Cloud NAT com IP estático reservado, regras de firewall de porta 22, upload da imagem para compilação serverless via Cloud Build, cluster de workstations, configuração blindada de segurança e a instância de workstation individual do desenvolvedor).*

---

## 🧪 5. Guia de Homologação e Testes Práticos (Para Fazer com o Cliente)

Abaixo está o roteiro de testes passo a passo para validar cada camada de segurança de forma visual e comprovada na frente do cliente:

### Teste A: Verificação de Aplicações Corporativas (Chrome)
1. No console do GCP, inicie a workstation criada e abra o **Code OSS** no navegador.
2. Abra o terminal integrado do Code OSS e execute:
   ```bash
   google-chrome --version
   ```
   *Resultado esperado:* O terminal deve retornar a versão oficial instalada estável do Google Chrome, comprovando que a imagem customizada foi montada com sucesso.

### Teste B: Imutabilidade e Autocura do Documento de Diretrizes
1. No terminal do Code OSS, verifique que o arquivo `AGENTS.md` está visível na raiz do workspace do usuário (`/home/user/AGENTS.md`).
2. Tente editar e salvar o arquivo diretamente no editor Code OSS.
   - *Resultado esperado:* O editor exibirá um erro de permissão bloqueando a gravação (`Permission Denied`), provando que as diretrizes são de posse do `root` e não podem ser adulteradas pelo desenvolvedor comum.
3. No terminal, force a exclusão do arquivo:
   ```bash
   rm /home/user/AGENTS.md
   ```
4. Reinicie a workstation (pare e inicie novamente pelo console do GCP ou pelo botão da IDE).
   - *Resultado esperado:* O arquivo `AGENTS.md` reaparece intacto! Nosso script de boot `/etc/workstation-startup.d/210_link_agents.sh` detectou a ausência e recriou o link simbólico automaticamente.

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

### Teste E: Bloqueio de Push para Contas Pessoais (DLP Ativo)
Este teste valida a barreira de prevenção de vazamento de dados em duas frentes de controle:

1. **Tentativa de Push por Repositório Não Autorizado (Filtro local do container)**:
   - Tente associar o repositório local a um destino pessoal do desenvolvedor fora do escopo corporativo:
     ```bash
     git remote set-url origin https://github.com/perfil-pessoal/repositorio-vazado.git
     git push origin main
     ```
   - *Resultado esperado:* O comando será cancelado imediatamente pelo hook de segurança local `pre-push` do container, retornando o seguinte aviso:
     `🚨 ERRO: TENTATIVA DE EXFILTRAÇÃO DETECTADA 🚨`
     `Neste ambiente, pushes são autorizados apenas para a org: sua-empresa`

2. **Tentativa de Push Não Autorizada de Rede (Regras do Secure Web Proxy - L7)**:
   - No setup produtivo real com SWP e TLS Inspection habilitados, qualquer chamada HTTP contendo rotas ou URLs destinadas a namespaces não-corporativos (como `https://github.com/perfil-pessoal/...`) para operações de gravação (`POST`) é barrada na camada de rede pelo proxy, retornando um erro de rede `HTTP 403 Forbidden`.

---

## 📈 6. Resumo Técnico das Camadas de Defesa (Defense in Depth)

| Camada de Controle | Tecnologia GCP / Mecanismo | Proteção Efetiva contra Ameaças |
| :--- | :--- | :--- |
| **1. Rede (Egress Control)** | VPC Firewalls (Bloqueio Porta 22) | Impede desvios binários criptografados que usam SSH para vazar dados. Força tráfego de Git para HTTPS. |
| **2. Proxy Granular (L7)** | Secure Web Proxy + TLS Inspection | Analisa caminhos de URL de saída corporativos vs. pessoais, bloqueando escritas fora do domínio corporativo. |
| **3. Whitelisting de IP** | Cloud NAT com IPs Estáticos Fixos | Permite bloquear acessos externos às contas corporativas de GitHub/Bitbucket. Somente IPs cadastrados das workstations acessam o SaaS. |
| **4. Endurecimento Local (DLP)** | Global `/etc/gitconfig` + `pre-push` hook imutável | Oferece validação redundante e independente direto no container. Sob posse exclusiva do `root`, bloqueia alterações locais do usuário. |
| **5. Isolamento de Identidade** | GitHub EMU e Atlassian Guard | Alinha identidades com o Provedor de Identidade corporativo (IdP) e desabilita a criação de repositórios pessoais na mesma conta. |
| **6. Políticas de Governança** | Idle Timeout de 30min + Auto-stop diário | Mitiga riscos de sessões órfãs ou expostas e reduz drasticamente o consumo e os custos de infraestrutura do GCP. |

Com essa estrutura robusta e o material trilíngue impecável, você está extremamente preparada para realizar uma apresentação de altíssimo nível para o seu cliente corporativo! Se precisar de qualquer suporte adicional, estou totalmente à disposição. 🚀
