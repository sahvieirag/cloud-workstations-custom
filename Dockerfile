# Usar a imagem oficial e homologada do Code OSS para Cloud Workstations
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

USER root

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
#    - Define um diretório de templates global para injetar githooks de proteção em novos repositórios.
RUN printf '[url "https://github.com/"]\n\tinsteadOf = git@github.com:\n[url "https://bitbucket.org/"]\n\tinsteadOf = git@bitbucket.org:\n[init]\n\ttemplateDir = /etc/git/templates\n' > /etc/gitconfig \
    && chmod 644 /etc/gitconfig

# 2. Criar a estrutura base de templates com um gancho 'pre-push' de segurança ativo
#    - Intercepta tentativas de 'git push' locais e bloqueia destinos que não sejam corporativos.
#    - O desenvolvedor padrão (user:1000) não consegue desativar esse hook do sistema.
RUN mkdir -p /etc/git/templates/hooks
RUN printf '#!/bin/bash\n# Pre-push hook de segurança do sistema\nALLOWED_ORG="sua-empresa"\nwhile read local_ref local_sha remote_ref remote_sha; do\n\tREMOTE_URL=$(git remote get-url origin 2>/dev/null)\n\tif [[ ! "$REMOTE_URL" =~ (github\\.com|bitbucket\\.org)/$ALLOWED_ORG/ ]]; then\n\t\techo "=========================================================="\n\t\techo "🚨 ERRO: TENTATIVA DE EXFILTRAÇÃO DETECTADA 🚨"\n\t\techo "Tentativa de push para repositório não corporativo: $REMOTE_URL"\n\t\techo "Neste ambiente, pushes são autorizados apenas para a org: $ALLOWED_ORG"\n\t\techo "=========================================================="\n\t\texit 1\n\tfi\ndone\nexit 0\n' > /etc/git/templates/hooks/pre-push \
    && chmod 755 /etc/git/templates/hooks/pre-push

# 3. Preparar diretório para certificados CA corporativos adicionais (TLS Inspection do Proxy)
#    - Indispensável para que a workstation reconheça o certificado de decodificação do Secure Web Proxy.
RUN mkdir -p /usr/local/share/ca-certificates/corp-proxy \
    && touch /usr/local/share/ca-certificates/corp-proxy/README.md \
    && echo "Coloque os certificados .crt da CA do seu proxy aqui e execute update-ca-certificates" > /usr/local/share/ca-certificates/corp-proxy/README.md

# Copiar o script de inicialização para o diretório workstation-startup.d
# Usamos o prefixo 210 para garantir que ele seja executado após a montagem do disco e scripts internos do GCP (que vão de 000 a 110)
COPY scripts/210_link_agents.sh /etc/workstation-startup.d/210_link_agents.sh
RUN chmod +x /etc/workstation-startup.d/210_link_agents.sh

# Retornar o contexto de execução para o usuário de desenvolvimento padrão (user com UID 1000)
# Isso impede que o usuário final acesse a IDE ou terminais padrão como root
USER user

