#!/bin/bash
# ==============================================================================
# Script de Inicialização Corporativa das Cloud Workstations
# Roda automaticamente como root no boot do container, após a montagem do /home
# ==============================================================================

echo "=== [START] Inicializando Configurações Corporativas de Segurança ==="

# 1. Garantir integridade do link de diretrizes de desenvolvimento (AGENTS.md)
TARGET_LINK="/home/user/AGENTS.md"
SOURCE_FILE="/etc/security/AGENTS.md"

if [ -f "$SOURCE_FILE" ]; then
    if [ ! -L "$TARGET_LINK" ] && [ ! -f "$TARGET_LINK" ]; then
        echo "Criando link de autocura para as diretrizes de desenvolvimento..."
        ln -sf "$SOURCE_FILE" "$TARGET_LINK"
        chown -h user:user "$TARGET_LINK"
    elif [ ! -L "$TARGET_LINK" ] || [ "$(readlink "$TARGET_LINK")" != "$SOURCE_FILE" ]; then
        echo "Corrigindo link de autocura corrompido..."
        rm -f "$TARGET_LINK"
        ln -sf "$SOURCE_FILE" "$TARGET_LINK"
        chown -h user:user "$TARGET_LINK"
    fi
else
    echo "🚨 AVISO: Diretrizes corporativas em $SOURCE_FILE não encontradas!"
fi

# 2. Atualizar CA Certificates se houver novos certificados corporativos de Proxy
if [ -d "/usr/local/share/ca-certificates/corp-proxy" ]; then
    # Verifica se há arquivos .crt além do README.md
    if ls /usr/local/share/ca-certificates/corp-proxy/*.crt >/dev/null 2>&1; then
        echo "Novos certificados CA corporativos detectados, atualizando sistema..."
        update-ca-certificates --fresh
    fi
fi

# 3. Exemplo conceitual de busca de credenciais de forma segura via Google Secret Manager no boot
# (Garante que tokens corporativos fiquem protegidos na nuvem e nunca 'hardcoded')
#
# if gcloud auth print-access-token >/dev/null 2>&1; then
#     echo "Acessando Google Secret Manager para obter token de clone seguro..."
#     CORP_TOKEN=$(gcloud secrets versions access latest --secret="git-corporate-token" 2>/dev/null)
#     if [ ! -z "$CORP_TOKEN" ]; then
#         # Configura credencial para clonagem via HTTPS
#         sudo -u user git config --global credential.helper 'store --file=/home/user/.git-credentials'
#         echo "https://oauth2:${CORP_TOKEN}@github.com" > /home/user/.git-credentials
#         chown user:user /home/user/.git-credentials
#         chmod 600 /home/user/.git-credentials
#         echo "Credenciais corporativas injetadas com sucesso via Secret Manager."
#     fi
# fi

echo "=== [END] Configurações Corporativas Concluídas com Sucesso ==="
