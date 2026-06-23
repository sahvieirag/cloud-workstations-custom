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

# Copiar o script de inicialização para o diretório workstation-startup.d
# Usamos o prefixo 210 para garantir que ele seja executado após a montagem do disco e scripts internos do GCP (que vão de 000 a 110)
COPY scripts/210_link_agents.sh /etc/workstation-startup.d/210_link_agents.sh
RUN chmod +x /etc/workstation-startup.d/210_link_agents.sh

# Retornar o contexto de execução para o usuário de desenvolvimento padrão (user com UID 1000)
# Isso impede que o usuário final acesse a IDE ou terminais padrão como root
USER user
