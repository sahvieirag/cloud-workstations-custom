#!/bin/bash
# Script de inicialização para criar o link simbólico autocura para AGENTS.md
# Este script roda como root no boot do container, após a montagem do disco persistente /home

echo "=== Executando Script de Inicialização das Diretrizes de Segurança ==="

TARGET_LINK="/home/user/AGENTS.md"
SOURCE_FILE="/etc/security/AGENTS.md"

# Garante que o arquivo de origem existe
if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERRO: Arquivo de origem $SOURCE_FILE não encontrado!"
    exit 1
fi

# Cria o link simbólico se ele não existir
if [ ! -L "$TARGET_LINK" ] && [ ! -f "$TARGET_LINK" ]; then
    echo "Criando link simbólico para as diretrizes de segurança..."
    ln -sf "$SOURCE_FILE" "$TARGET_LINK"
    chown -h user:user "$TARGET_LINK"
    echo "Link simbólico criado com sucesso em $TARGET_LINK."
else
    # Se já existir mas não for link simbólico ou estiver apontando para outro lugar, corrige
    if [ ! -L "$TARGET_LINK" ] || [ "$(readlink "$TARGET_LINK")" != "$SOURCE_FILE" ]; then
        echo "Corrigindo link simbólico corrompido ou arquivo modificado..."
        rm -f "$TARGET_LINK"
        ln -sf "$SOURCE_FILE" "$TARGET_LINK"
        chown -h user:user "$TARGET_LINK"
        echo "Link simbólico corrigido e redefinido."
    else
        echo "O link simbólico de segurança já está presente e correto."
    fi
fi

echo "=== Script de Diretrizes de Segurança Concluído ==="
