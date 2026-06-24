#!/bin/bash

# ==============================================================================
# SCRIPT DE SETUP AUTOMATIZADO - GOOGLE CLOUD WORKSTATIONS SEGURO (IDEMPOTENTE)
# Foco: Restrição Estrita de SaaS Cloud (GitHub.com & Bitbucket.org)
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

# Organização Corporativa Autorizada (Placeholder para o cliente)
CORP_ORG_NAME="sua-empresa"

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
echo "Organização Corporativa de Teste: ${CORP_ORG_NAME}"
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
    compute.googleapis.com \
    networksecurity.googleapis.com # Necessário para o Secure Web Proxy se ativado

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
    # Permite baixar imagens do Artifact Registry internamente sem IPs públicos.
    gcloud compute networks subnets create "${SUBNET_NAME}" \
        --network="${VPC_NAME}" \
        --range="${SUBNET_RANGE}" \
        --region="${REGION}" \
        --enable-private-ip-google-access
fi

# ==============================================================================
# 4. ALOCAÇÃO DE IP PÚBLICO ESTÁTICO E CONFIGURAÇÃO DE CLOUD NAT (MELHOR PRÁTICA)
# ==============================================================================
# No ambiente de produção do cliente, ter IPs de saída (Egress) fixos e estáticos é
# fundamental. Isso permite fazer o "IP Whitelisting" no GitHub Enterprise e Bitbucket,
# garantindo que o tráfego SaaS só seja liberado se vier do IP fixo do Cloud NAT.

ROUTER_NAME="workstations-router"
NAT_NAME="workstations-nat"
STATIC_IP_NAME="workstations-nat-static-ip"

if gcloud compute routers describe "${ROUTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Cloud Router '${ROUTER_NAME}' já existe. Pulando."
else
    echo "[STEP] Criando Cloud Router para o gateway NAT..."
    gcloud compute routers create "${ROUTER_NAME}" \
        --network="${VPC_NAME}" \
        --region="${REGION}"
fi

# 1. Reservar o IP externo estático para o NAT se não existir
if gcloud compute addresses describe "${STATIC_IP_NAME}" --region="${REGION}" &>/dev/null; then
    echo "IP Estático '${STATIC_IP_NAME}' já reservado."
else
    echo "[STEP] Reservando endereço IP público estático para o NAT (IP Whitelisting)..."
    gcloud compute addresses create "${STATIC_IP_NAME}" --region="${REGION}"
fi

NAT_IP_ADDRESS=$(gcloud compute addresses describe "${STATIC_IP_NAME}" --region="${REGION}" --format="value(address)")
echo "Endereço IP Estático Reservado: ${NAT_IP_ADDRESS}"

# 2. Criar o gateway Cloud NAT associando o IP estático
if gcloud compute routers nats describe "${NAT_NAME}" --router="${ROUTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "Cloud NAT '${NAT_NAME}' já existe. Pulando."
else
    echo "[STEP] Criando gateway Cloud NAT com IP estático alocado..."
    gcloud compute routers nats create "${NAT_NAME}" \
        --router="${ROUTER_NAME}" \
        --region="${REGION}" \
        --nat-external-ip-pool="${STATIC_IP_NAME}" \
        --nat-all-subnet-ip-ranges
fi

# ==============================================================================
# 4.1 REGRAS DE FIREWALL - BLOQUEIO DE SSH DE SAÍDA (L4)
# ==============================================================================
# Para forçar o Git a usar o protocolo HTTPS (porta 443) onde as URLs podem ser
# inspecionadas por URL Path Filtering no proxy, devemos bloquear a porta 22 (SSH)
# de saída de todas as workstations na VPC.

FIREWALL_DENY_SSH="deny-egress-ssh-port-22"

if gcloud compute firewall-rules describe "${FIREWALL_DENY_SSH}" &>/dev/null; then
    echo "Regra de firewall '${FIREWALL_DENY_SSH}' já existe. Pulando."
else
    echo "[STEP] Criando regra de firewall para bloquear saída SSH (Porta 22)..."
    gcloud compute firewall-rules create "${FIREWALL_DENY_SSH}" \
        --network="${VPC_NAME}" \
        --direction=EGRESS \
        --action=DENY \
        --rules=tcp:22 \
        --priority=1000 \
        --description="Impede conexao SSH de saida para garantir uso do HTTPS com inspecao de pacotes"
fi

# ==============================================================================
# 4.2 [EXEMPLO DE POSSIBILIDADE ARQUITETURAL] - CLOUD SECURE WEB PROXY (SWP)
# ==============================================================================
# ATENÇÃO: Os comandos abaixo servem como guia e EXEMPLO DE POSSIBILIDADE técnica.
# Eles mostram como o cliente pode criar regras de Secure Web Proxy (SWP) com TLS
# Inspection para descriptografar conexões e filtrar caminhos estritamente corporativos
# (ex: github.com/sua-empresa/*) e bloquear namespaces pessoais de push.
#
# Em cenários de teste simples ou prototipação flexível com a Sabrina, essas regras
# podem ficar como referencial técnico para que o cliente veja as possibilidades de design.

cat << 'EOF'

================================================================================
💡 GUIA ARQUITETURAL: PROVISIONANDO O SECURE WEB PROXY (SWP) COM TLS INSPECTION
================================================================================
O Secure Web Proxy permite inspecionar caminhos HTTPS decodificados. Caso o cliente
queira implementar esse nível de proteção absoluta, o roteiro técnico é o seguinte:

# 1. Criar uma subrede dedicada para proxies regionais gerenciados (obrigatório para o SWP)
# gcloud compute networks subnets create swp-proxy-subnet \
#     --purpose=REGIONAL_MANAGED_PROXY \
#     --role=ACTIVE \
#     --region=us-central1 \
#     --network=workstations-vpc \
#     --range=10.129.0.0/23

# 2. Criar a política de inspeção de TLS (carregar a CA privada da empresa no GCP)
# gcloud network-security tls-inspection-policies create corp-tls-policy \
#     --location=us-central1 \
#     --ca-pool=projects/PROJETO/locations/us-central1/caPools/SUA-CA \
#     --trust-config=projects/PROJETO/locations/us-central1/trustConfigs/SUA-TRUST-CONFIG

# 3. Definir regras de roteamento baseadas em URL Path no Gateway Security Policy
# Criar regras que liberem GET (clone/pull) para a organização e bloqueiem POST (push) pessoais:
# Rule A (Clone Corporativo): ALLOW para GET/POST em 'github.com/sua-empresa/*' e 'bitbucket.org/sua-empresa/*'
# Rule B (Público Geral - Opcional): ALLOW para GET (leitura apenas) em repositórios públicos para bibliotecas
# Rule C (Push Pessoal): DENY para POST em qualquer outro caminho de 'github.com/*' ou 'bitbucket.org/*'

================================================================================
EOF

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
echo " - Egress SSH (Porta 22) BLOQUEADO de forma estrita"
echo " - Cloud NAT active com IP público estático fixo: ${NAT_IP_ADDRESS}"
echo " - Imagem Customizada no Artifact Registry: ${IMAGE_URI}"
echo " - Cluster do Cloud Workstations: ${CLUSTER_NAME}"
echo " - Configuração Blindada: ${CONFIG_NAME} (Sem IP público, Auto-stop ativo)"
echo " - Workstation do Desenvolvedor: ${WORKSTATION_NAME}"
echo " - Permissão concedida exclusivamente a: ${DEV_EMAIL}"
echo "============================================================"
