# Imagem base homologada do Code OSS para Cloud Workstations
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

USER root

# Instalar dependências do sistema operacional e Google Chrome Stable
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

# Criar diretório de segurança interna e copiar guia de diretrizes
RUN mkdir -p /etc/security
COPY config/AGENTS.md /etc/security/AGENTS.md
RUN chmod 644 /etc/security/AGENTS.md

# Redirecionar SSH para HTTPS globalmente e forçar hooks globais do Git
RUN printf '[url "https://github.com/"]\n\tinsteadOf = git@github.com:\n[url "https://bitbucket.org/"]\n\tinsteadOf = git@bitbucket.org:\n[core]\n\thooksPath = /etc/git/hooks\n' > /etc/gitconfig \
    && chmod 644 /etc/gitconfig

# Criar gancho pre-push global para prevenção ativa de vazamento de código
RUN mkdir -p /etc/git/hooks
RUN printf '#!/bin/bash\n# Global pre-push hook de seguranca\n\nORG_PERMITIDA="${ALLOWED_ORG:-sua-empresa}"\n\nwhile read local_ref local_sha remote_ref remote_sha; do\n\tREMOTE_URL=$(git remote get-url origin 2>/dev/null)\n\tif [[ ! "$REMOTE_URL" =~ (github\\.com|bitbucket\\.org)/$ORG_PERMITIDA/ ]]; then\n\t\techo "=========================================================="\n\t\techo "🚨 ERRO: TENTATIVA DE EXFILTRAÇÃO DETECTADA 🚨"\n\t\techo "Pushes autorizados apenas para a org corporativa: $ORG_PERMITIDA"\n\t\techo "=========================================================="\n\t\texit 1\n\tfi\ndone\nexit 0\n' > /etc/git/hooks/pre-push \
    && chmod 755 /etc/git/hooks/pre-push

# Preparar diretório para certificados públicos da Subordinate CA do Secure Web Proxy
RUN mkdir -p /usr/local/share/ca-certificates/corp-proxy \
    && touch /usr/local/share/ca-certificates/corp-proxy/README.md \
    && echo "Coloque os certificados .crt da CA do proxy aqui para update-ca-certificates" > /usr/local/share/ca-certificates/corp-proxy/README.md

# Copiar script de inicialização automática executado como root no boot
COPY scripts/210_setup_corporate_git.sh /etc/workstation-startup.d/210_setup_corporate_git.sh
RUN chmod +x /etc/workstation-startup.d/210_setup_corporate_git.sh

# O container inicia como root para montagem de discos; a IDE executa sob UID 1000
