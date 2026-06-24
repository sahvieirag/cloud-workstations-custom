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

# 2. Buscar dinamicamente o certificado da CA privada do Google Cloud (para o TLS Inspection)
CA_CERT_PATH="/usr/local/share/ca-certificates/corp-proxy/secure-workstations-sub-ca.crt"
if [ -d "/usr/local/share/ca-certificates/corp-proxy" ] && [ ! -f "$CA_CERT_PATH" ]; then
    echo "Tentando buscar certificado da CA privada do Google Cloud..."
    # Obtém o Project ID dinamicamente do servidor de metadados do GCP para manter a imagem 100% portátil
    GCP_PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.com/computeMetadata/v1/project/project-id 2>/dev/null)
    if [ -n "$GCP_PROJECT" ]; then
        # Tenta descrever a sub-CA usando as credenciais da Service Account da Workstation
        if gcloud privateca subordinates describe secure-workstations-sub-ca \
            --pool=secure-workstations-ca-pool \
            --location=us-central1 \
            --project="$GCP_PROJECT" \
            --format="value(pemCaCertificates)" > "$CA_CERT_PATH" 2>/dev/null; then
            echo "Certificado da CA privada obtido e salvo com sucesso em $CA_CERT_PATH!"
        else
            echo "🚨 AVISO: Não foi possível obter o certificado da CA via gcloud. Verifique se a Service Account possui 'roles/privateca.auditor' no projeto $GCP_PROJECT."
        fi
    else
        echo "🚨 AVISO: Não foi possível detectar o ID do projeto do GCP via servidor de metadados."
    fi
fi

# 3. Atualizar CA Certificates se houver novos certificados de Proxy adicionados
if [ -d "/usr/local/share/ca-certificates/corp-proxy" ]; then
    # Verifica se há arquivos .crt além do README.md
    if ls /usr/local/share/ca-certificates/corp-proxy/*.crt >/dev/null 2>&1; then
        echo "Atualizando o trust store de certificados CA do sistema operacional..."
        update-ca-certificates --fresh
    fi
fi

echo "=== [END] Configurações Corporativas Concluídas com Sucesso ==="
