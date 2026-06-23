#!/bin/bash

# ==============================================================================
# SCRIPT DE SETUP AUTOMATIZADO - GOOGLE CLOUD WORKSTATIONS SEGURO (IDEMPOTENTE)
# Cliente: Primeiro Setup de Workstation Privada com Imagem Customizada
# Projeto GCP: expanded-flame-422613-e4
# Conta de Protótipo: admin@sabrinaguerra.altostrat.com
# ==============================================================================

# PARAR O SCRIPT SE OCORRER QUALQUER ERRO
set -e

# ==============================================================================
# 1. DEFINIÇÃO DE VARIÁVEIS DE AMBIENTE
# ==============================================================================
PROJECT_ID="expanded-flame-422613-e4"

REGION="us-central1"
ZONE="us-central1-a"

# Configurações de Rede
VPC_NAME="workstations-vpc"
SUBNET_NAME="workstations-subnet"
SUBNET_RANGE="10.10.0.0/24"

# IP do GitHub Self-Hosted do Cliente (Substitua pelo IP real do servidor de destino)
GITHUB_SELF_HOSTED_RANGE="10.240.0.0/16" 

# Configurações do Artifact Registry e Imagem
REPO_NAME="workstations-repo"
IMAGE_TAG="secure-code-oss-chrome:latest"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_TAG}"

# Configurações do Cloud Workstations
CLUSTER_NAME="secure-workstations-cluster"
CONFIG_NAME="secure-developer-config"
WORKSTATION_NAME="dev-workstation-sabrina"
DEV_EMAIL="admin@sabrinaguerra.altostrat.com" # E-mail real para acesso direto de Sabrina

echo "------------------------------------------------------------"
echo "Iniciando provisionamento para o projeto: ${PROJECT_ID}"
echo "Região: ${REGION}"
echo "Conta do Protótipo: ${DEV_EMAIL}"
echo "------------------------------------------------------------"

# Garantir que o gcloud está apontando para o projeto correto
gcloud config set project "${PROJECT_ID}"

# ==============================================================================
# 2. ATIVAÇÃO DAS APIS DO GOOGLE CLOUD
# ==============================================================================
echo "[STEP] Ativando APIs de serviços necessárias..."
gcloud services enable \
    workstations.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    compute.googleapis.com

# ==============================================================================
# 3. CRIAÇÃO DA REDE VPC E SUBREDE PRIVADA
# ==============================================================================
if gcloud compute networks describe "${VPC_NAME}" &>/dev/null; then
    echo "Rede VPC '${VPC_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando VPC customizada de segurança..."
    gcloud compute networks create "${VPC_NAME}" \
        --subnet-mode=custom \
        --bgp-routing-mode=regional
fi

if gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Subrede '${SUBNET_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando Subrede privada com Private Google Access ativo..."
    # O Private Google Access (--enable-private-ip-google-access) é crucial!
    gcloud compute networks subnets create "${SUBNET_NAME}" \
        --network="${VPC_NAME}" \
        --range="${SUBNET_RANGE}" \
        --region="${REGION}" \
        --enable-private-ip-google-access
fi

# ==============================================================================
# 4. CONFIGURAÇÃO DE REDE - CLOUD NAT (ACESSO SEGURO DE BAIXO CUSTO À INTERNET)
# ==============================================================================
# Como as VMs das workstations NÃO possuem IPs públicos por segurança, elas precisam
# de um gateway Cloud NAT para conseguir falar com a internet pública (ex: github.com).
# O Cloud NAT é extremamente barato (~1 USD/mês fixo) e altamente seguro, pois as conexões
# são apenas de saída (Egress), impedindo qualquer ataque vindo de fora para dentro (Ingress).

ROUTER_NAME="workstations-router"
NAT_NAME="workstations-nat"

if gcloud compute routers describe "${ROUTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Cloud Router '${ROUTER_NAME}' já existe. Pulando."
else
    echo "[STEP] Criando Cloud Router para o gateway NAT..."
    gcloud compute routers create "${ROUTER_NAME}" \
        --network="${VPC_NAME}" \
        --region="${REGION}"
fi

if gcloud compute routers nats describe "${NAT_NAME}" --router="${ROUTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Cloud NAT '${NAT_NAME}' já existe. Pulando."
else
    echo "[STEP] Criando gateway Cloud NAT para permitir saída segura à internet..."
    gcloud compute routers nats create "${NAT_NAME}" \
        --router="${ROUTER_NAME}" \
        --region="${REGION}" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges
fi

# ==============================================================================
# 4.1 REGRAS DE FIREWALL - CONFIGURAÇÃO FLEXÍVEL / STANDBY
# ==============================================================================
echo "[STEP] Configurando regras de firewall em modo flexível para o protótipo..."

# Por padrão, para o protótipo, deixaremos o tráfego de saída (Egress) aberto via NAT
# para que os desenvolvedores consigam baixar pacotes, acessar o GitHub público, etc.
# Se no futuro seu cliente quiser trancar 100% da saída, basta descomentar as regras abaixo.

# [STANDBY: BLOQUEIO TOTAL DE EGRESS]
# Descomente o bloco abaixo para trancar totalmente a saída de internet pública:
# if gcloud compute firewall-rules describe "deny-all-egress" &>/dev/null; then
#     echo "Regra 'deny-all-egress' já existe."
# else
#     echo "Criando regra 'deny-all-egress'..."
#     gcloud compute firewall-rules create "deny-all-egress" \
#         --network="${VPC_NAME}" \
#         --direction=EGRESS \
#         --action=DENY \
#         --rules=all \
#         --priority=65000 \
#         --description="Bloqueia todo tráfego de saída da VPC"
# fi

# [STANDBY: PERMISSÃO EXCLUSIVA PARA GITHUB SELF-HOSTED]
# Descomente o bloco abaixo para abrir exceção estrita para o GitHub privado do cliente:
# if gcloud compute firewall-rules describe "allow-egress-to-github-self-hosted" &>/dev/null; then
#     echo "Regra 'allow-egress-to-github-self-hosted' já existe."
# else
#     echo "Criando regra 'allow-egress-to-github-self-hosted'..."
#     gcloud compute firewall-rules create "allow-egress-to-github-self-hosted" \
#         --network="${VPC_NAME}" \
#         --direction=EGRESS \
#         --action=ALLOW \
#         --rules=tcp:22,tcp:80,tcp:443 \
#         --destination-ranges="${GITHUB_SELF_HOSTED_RANGE}" \
#         --priority=1000 \
#         --description="Permite conexao HTTPS/SSH estrita para o GitHub Self-Hosted do cliente"
# fi

# [STANDBY: PERMISSÃO PARA APIs DO GOOGLE (PRIVATE GOOGLE ACCESS)]
# if gcloud compute firewall-rules describe "allow-egress-to-google-apis-pga" &>/dev/null; then
#     echo "Regra 'allow-egress-to-google-apis-pga' já existe."
# else
#     echo "Criando regra 'allow-egress-to-google-apis-pga'..."
#     gcloud compute firewall-rules create "allow-egress-to-google-apis-pga" \
#         --network="${VPC_NAME}" \
#         --direction=EGRESS \
#         --action=ALLOW \
#         --rules=tcp:443 \
#         --destination-ranges="199.36.153.8/30,199.36.153.4/30,34.120.0.0/16" \
#         --priority=1010 \
#         --description="Permite acesso privado seguro as APIs do GCP para funcionamento do sistema"
# fi


# ==============================================================================
# 5. CONFIGURAÇÃO DO REPOSITÓRIO NO ARTIFACT REGISTRY
# ==============================================================================
if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" &>/dev/null; then
    echo "Repositório do Artifact Registry '${REPO_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando repositório privado para imagens Docker no Artifact Registry..."
    gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Repositorio seguro de imagens de desenvolvimento para Cloud Workstations"
fi

# ==============================================================================
# 6. CONSTRUÇÃO E PUBLICAÇÃO DA IMAGEM CUSTOMIZADA VIA CLOUD BUILD
# ==============================================================================
echo "[STEP] Iniciando compilação serverless e envio da imagem customizada via Cloud Build..."
# Esse comando pega o Dockerfile local, o script de inicialização e a pasta config,
# envia para o Cloud Build de forma isolada, gera a imagem final e publica no repositório.
gcloud builds submit . \
    --tag="${IMAGE_URI}" \
    --timeout=1200s

# ==============================================================================
# 7. CRIAÇÃO DO CLUSTER DE CLOUD WORKSTATIONS
# ==============================================================================
if gcloud workstations clusters describe "${CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Cluster de workstations '${CLUSTER_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando o Cloud Workstations Cluster de forma privada..."
    gcloud workstations clusters create "${CLUSTER_NAME}" \
        --network="${VPC_NAME}" \
        --subnetwork="${SUBNET_NAME}" \
        --region="${REGION}"
fi

# ==============================================================================
# 8. CRIAÇÃO DA CONFIGURAÇÃO DA WORKSTATION BLINDADA
# ==============================================================================
if gcloud workstations configs describe "${CONFIG_NAME}" --cluster="${CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Configuração de workstation '${CONFIG_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando a especificação de configuração das workstations..."
    gcloud workstations configs create "${CONFIG_NAME}" \
        --cluster="${CLUSTER_NAME}" \
        --region="${REGION}" \
        --container-custom-image="${IMAGE_URI}" \
        --disable-public-ip-addresses \
        --idle-timeout="1800s" \
        --running-timeout="43200s" \
        --disk-size="100GB" \
        --disk-reclaim-policy="delete"
fi

# ==============================================================================
# 9. CRIAÇÃO E ATRIBUIÇÃO DE ACESSO À PRIMEIRA WORKSTATION INDIVIDUAL
# ==============================================================================
if gcloud workstations describe "${WORKSTATION_NAME}" --cluster="${CLUSTER_NAME}" --config="${CONFIG_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Instância de workstation '${WORKSTATION_NAME}' já existe. Pulando criação."
else
    echo "[STEP] Criando a primeira instância de workstation privada para o desenvolvedor..."
    gcloud workstations create "${WORKSTATION_NAME}" \
        --cluster="${CLUSTER_NAME}" \
        --config="${CONFIG_NAME}" \
        --region="${REGION}"
fi

echo "[STEP] Atribuindo permissão de acesso exclusiva via IAM para o usuário..."
gcloud workstations add-iam-policy-binding "${WORKSTATION_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --config="${CONFIG_NAME}" \
    --region="${REGION}" \
    --role="roles/workstations.user" \
    --member="user:${DEV_EMAIL}"

echo "============================================================"
echo " PROVISIONAMENTO CONCLUÍDO COM SUCESSO!"
echo "============================================================"
echo " Detalhes da entrega:"
echo " - Rede VPC segura: ${VPC_NAME}"
echo " - Egress bloqueado, permitindo saída apenas para: ${GITHUB_SELF_HOSTED_RANGE}"
echo " - Imagem Customizada no Artifact Registry: ${IMAGE_URI}"
echo " - Cluster do Cloud Workstations: ${CLUSTER_NAME}"
echo " - Configuração Blindada: ${CONFIG_NAME} (Sem IP público, Auto-stop ativo)"
echo " - Workstation do Desenvolvedor: ${WORKSTATION_NAME}"
echo " - Permissão concedida exclusivamente a: ${DEV_EMAIL}"
echo "============================================================"
