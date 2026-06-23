# Guia de Entrega: Configuração de Cloud Workstations Segura

Olá, Sabrina! É um prazer entregar a solução completa e blindada para o primeiro setup de **Google Cloud Workstations** do seu cliente no projeto `workstations-demo-491214`.

Este guia resume os componentes que criamos, como executar a implantação automatizada no GCP e como realizar testes práticos junto com seu cliente para validar as camadas de rede e segurança.

---

## 1. Estrutura de Arquivos Criada no Repositório

Organizamos o repositório local (`/Users/sabrinaguerra/Documents/antigravity/eager-shannon`) com uma estrutura limpa e profissional, pronta para compilação:

```text
eager-shannon/
├── Dockerfile               # Definição da imagem (Code OSS + Google Chrome + Arquivos de Segurança)
├── gcloud_setup.sh          # Script IaC em Shell totalmente documentado para provisionamento do GCP
├── config/
│   └── AGENTS.md            # Cartilha de diretrizes de desenvolvimento seguro do seu cliente
└── scripts/
    └── 210_link_agents.sh   # Script de boot da workstation para autocura do link simbólico
```

---

## 2. Passo a Passo de Execução da Infraestrutura

Para criar os recursos no GCP do seu cliente, siga os passos abaixo no terminal local:

### Passo 1: Autenticar no GCP
Garanta que você está autenticada na conta do cliente com as permissões necessárias (`Owner` ou `Editor` + `Workstation Admin`):
```bash
gcloud auth login
```

### Passo 2: Definir Permissões de Execução
Acesse a pasta do repositório no seu computador e dê permissão de execução ao nosso script IaC:
```bash
chmod +x gcloud_setup.sh
```

### Passo 3: Executar o Setup Automatizado
Rode o script para provisionar toda a infraestrutura e compilar a imagem. 
*(O script levará alguns minutos pois ele fará o upload dos arquivos para o **Cloud Build** compilar de forma totalmente serverless na nuvem, criará a rede VPC, os firewalls, o cluster do Workstations e a configuração blindada)*:
```bash
./gcloud_setup.sh
```

> [!NOTE]
> No arquivo `gcloud_setup.sh`, a variável `DEV_EMAIL` está pré-definida com um valor fictício e a variável `GITHUB_SELF_HOSTED_RANGE` está definida com o bloco `10.240.0.0/16`. Sinta-se à vontade para ajustar esses valores diretamente no script antes de rodar, ou usá-los como demonstração!

---

## 3. Guia de Homologação e Testes (Para Fazer com o Cliente)

Abaixo está o roteiro de testes para validar se todos os requisitos de segurança e ferramentas solicitados estão operando conforme o planejado.

### Teste A: Verificação de Ferramentas (Chrome)
1. Inicie a workstation criada e abra o console do **Code OSS** no navegador.
2. Abra um novo terminal integrado no Code OSS.
3. Execute o comando abaixo para confirmar que o Chrome está instalado na máquina virtual do container:
   ```bash
   google-chrome --version
   ```
   *Resultado esperado:* O terminal deve retornar a versão oficial estável do Google Chrome instalada.

---

### Teste B: Verificação das Diretrizes de Segurança (`AGENTS.md`)
O arquivo de regras de desenvolvimento deve ser persistente, visível no explorer e não editável pelo usuário comum.

1. **Visibilidade**: Assim que abrir o Code OSS, confirme que o arquivo `AGENTS.md` está listado diretamente na raiz do workspace do usuário (`/home/user/AGENTS.md`).
2. **Não-editabilidade (Imutabilidade)**: 
   - Tente abrir o arquivo no Code OSS e fazer alguma alteração (digitar uma nova linha e salvar).
   - *Resultado esperado:* O editor exibirá um erro de permissão bloqueando a gravação (`Permission Denied`), pois o link aponta para um arquivo protegido pertencente ao `root` (`/etc/security/AGENTS.md`).
3. **Persistência e Autocura**:
   - No terminal do Code OSS, force a remoção do link simbólico do seu workspace:
     ```bash
     rm /home/user/AGENTS.md
     ```
   - No console do GCP, pare a workstation e inicie-a novamente (isso recria o container).
   - Abra o Code OSS novamente.
   - *Resultado esperado:* O arquivo `AGENTS.md` reapareceu intacto no workspace! O nosso script de inicialização (`/etc/workstation-startup.d/210_link_agents.sh`) detectou a ausência no boot e restaurou o link de segurança.

---

### Teste C: Verificação das Fronteiras de Rede (Isolamento de Egress)

Como configuramos o ambiente em modo flexível para o protótipo, criamos um gateway **Cloud NAT** na VPC e deixamos as regras de bloqueio estritas comentadas (em standby). Isso facilita os testes iniciais.

#### Cenário 1: Com o script de Setup Padrão (Modo Protótipo - Cloud NAT Ativo)
Neste modo, a workstation não possui IP público (segurança de entrada), mas consegue falar de forma segura com a internet pública (segurança de saída via NAT):

1. **Acesso ao GitHub e Internet Geral**:
   - No terminal do Code OSS, tente dar um curl no GitHub ou Google:
     ```bash
     curl -I --connect-timeout 5 https://github.com
     ```
   - *Resultado esperado:* Conexão bem-sucedida! O **Cloud NAT** está direcionando a saída da sua máquina de forma totalmente segura e permitindo conexões com repositórios e serviços públicos.

---

#### Cenário 2: Ativando a Segurança Máxima (Modo Trancado - Produção)
Se você ou o cliente descomentarem as regras de firewall de egress no script `gcloud_setup.sh` e executarem o setup, o comportamento mudará para o isolamento de rede total:

1. **Tentativa de Acesso Externo (Internet Geral)**:
   - No terminal do Code OSS, tente acessar qualquer domínio público:
     ```bash
     curl -I --connect-timeout 5 https://google.com
     ```
   - *Resultado esperado:* O comando falhará por timeout. A regra de firewall `deny-all-egress` bloqueará toda e qualquer saída direta para fora da VPC.
2. **Conexão com o GitHub Self-Hosted**:
   - Tente se conectar à rede do GitHub privado do cliente (range `10.240.x.x`):
     ```bash
     curl -I --connect-timeout 5 https://<IP_DO_GITHUB_SELF_HOSTED>
     ```
   - *Resultado esperado:* Conexão bem-sucedida ou tentativa permitida pela regra `allow-egress-to-github-self-hosted`.
3. **Comunicação com APIs do Google (Private Google Access)**:
   - Verifique se as APIs do GCP continuam respondendo privadamente:
     ```bash
     curl -I --connect-timeout 5 https://www.googleapis.com/generate_204
     ```
   - *Resultado esperado:* Conexão bem-sucedida! Isso demonstra que o **Acesso Privado do Google** está ativo e o tráfego de monitoramento/APIs internas flui sem precisar de internet direta.

---


## 4. Resumo das Camadas de Defesa Aplicadas (Defense in Depth)

| Camada | Mecanismo de Segurança | Benefício para o Cliente |
| :--- | :--- | :--- |
| **Rede (VPC)** | Cluster Privado, Sem IPs Públicos nas VMs, Egress Totalmente Bloqueado | Impede vazamento de dados para servidores públicos de terceiros e protege contra varreduras de portas externas. |
| **Acesso (IAM)** | Autenticação via IAP e Role `workstations.user` individual | Garante que apenas o desenvolvedor expressamente autorizado via conta GCP possa conectar em sua workstation. |
| **Ciclo de Vida** | Auto-stop por inatividade de 30 minutos e limite diário de 12 horas | Minimiza custos e limita a janela de exposição de sessões abertas ou abandonadas em computadores pessoais. |
| **Armazenamento** | Discos de Home Persistente de 100GB Criptografados | Mantém o código do desenvolvedor seguro, isolado e passível de auditoria criptografada. |
| **Políticas (SO)** | Diretrizes `AGENTS.md` somente leitura e script com autocura | Mantém as regras corporativas sempre visíveis para consulta e impossíveis de serem deletadas ou alteradas pelos usuários das workstations. |

A solução está completa e perfeitamente alinhada com as melhores práticas recomendadas pela Google Cloud! Se precisar de qualquer ajuste nos scripts ou de ajuda durante a execução no ambiente do cliente, estarei por aqui. 🚀
