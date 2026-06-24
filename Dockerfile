# Usar a imagem oficial e homologada do Code OSS para Cloud Workstations
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

USER root

# ==============================================================================
# CONFIGURAÇÃO DE PROXY CORPORATIVO
# ==============================================================================
# Define as variáveis de proxy de saída globais para que todas as ferramentas 
# e a própria IDE utilizem o Secure Web Proxy (SWP) corporativo automaticamente.
ENV http_proxy="http://[IP_DO_SEU_PROXY]:80" \
    https_proxy="http://[IP_DO_SEU_PROXY]:80" \
    no_proxy="metadata.google.internal,169.254.169.254,10.0.0.0/8" \
    HTTP_PROXY="http://[IP_DO_SEU_PROXY]:80" \
    HTTPS_PROXY="http://[IP_DO_SEU_PROXY]:80" \
    NO_PROXY="metadata.google.internal,169.254.169.254,10.0.0.0/8"

# Atualizar pacotes, instalar ferramentas básicas, adicionar a chave de criptografia do Chrome,
# configurar o repositório estável e instalar o Google Chrome Stable
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    gnupg \
    ca-certificates \
    && wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
    google-chrome-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Criar a pasta de segurança no sistema operacional e copiar o arquivo de diretrizes
RUN mkdir -p /etc/security
COPY config/AGENTS.md /etc/security/AGENTS.md
RUN chmod 644 /etc/security/AGENTS.md

# ==============================================================================
# HARDENING DO GIT E SEGURANÇA CONTRA EXFILTRAÇÃO (REQUISITO CORPORATIVO)
# ==============================================================================
# 1. Configurar o Git global do sistema de forma imutável (apenas leitura para o usuário)
#    - Redireciona conexões SSH para HTTPS para garantir que passem pelo Secure Web Proxy (SWP).
#    - Configura core.hooksPath globalmente para forçar a execução de ganchos de segurança
#      em TODOS os repositórios da máquina (atuais ou novos), impedindo bypass local.
RUN printf '[url "https://github.com/"]\n\tinsteadOf = git@github.com:\n[url "https://bitbucket.org/"]\n\tinsteadOf = git@bitbucket.org:\n[core]\n\thooksPath = /etc/git/hooks\n' > /etc/gitconfig \
    && chmod 644 /etc/gitconfig

# 2. Criar a pasta de ganchos globais e implementar o 'pre-push' hook de proteção ativo
#    - Intercepta todas as tentativas de 'git push' locais e bloqueia destinos não corporativos.
#    - Lê a variável de ambiente $ALLOWED_ORG injetável dinamicamente nas configurações do GCP,
#      evitando a necessidade de recompilar a imagem para organizações ou departamentos distintos.
RUN mkdir -p /etc/git/hooks
RUN printf '#!/bin/bash\n# Global pre-push hook de segurança das Cloud Workstations\n\nORG_PERMITIDA="${ALLOWED_ORG:-sua-empresa}"\n\nwhile read local_ref local_sha remote_ref remote_sha; do\n\tREMOTE_URL=$(git remote get-url origin 2>/dev/null)\n\tif [[ ! "$REMOTE_URL" =~ (github\\.com|bitbucket\\.org)/$ORG_PERMITIDA/ ]]; then\n\t\techo "=========================================================="\n\t\techo "🚨 ERRO: TENTATIVA DE EXFILTRAÇÃO DETECTADA 🚨"\n\t\techo "Tentativa de push para repositório não corporativo: $REMOTE_URL"\n\t\techo "Neste ambiente, pushes são autorizados apenas para a org: $ORG_PERMITIDA"\n\t\techo "=========================================================="\n\t\texit 1\n\tfi\ndone\nexit 0\n' > /etc/git/hooks/pre-push \
    && chmod 755 /etc/git/hooks/pre-push

# 3. Preparar diretório para certificados CA corporativos adicionais (TLS Inspection do Proxy)
#    - Indispensável para que a workstation reconheça o certificado de decodificação do Secure Web Proxy.
RUN mkdir -p /usr/local/share/ca-certificates/corp-proxy \
    && touch /usr/local/share/ca-certificates/corp-proxy/README.md \
    && echo "Coloque os certificados .crt da CA do seu proxy aqui e execute update-ca-certificates" > /usr/local/share/ca-certificates/corp-proxy/README.md

# Copiar o script de inicialização corporativa para o diretório workstation-startup.d
# O script roda como root em todo boot e corrige links do workspace após a montagem do disco persistente (/home)
COPY scripts/210_setup_corporate_git.sh /etc/workstation-startup.d/210_setup_corporate_git.sh
RUN chmod +x /etc/workstation-startup.d/210_setup_corporate_git.sh

# Retornar o contexto de execução para o usuário de desenvolvimento padrão (user com UID 1000)
# Isso impede que o usuário final acesse a IDE ou terminais padrão como root
USER user
