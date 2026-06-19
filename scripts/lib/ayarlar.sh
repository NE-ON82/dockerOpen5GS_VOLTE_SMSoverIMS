#!/usr/bin/env bash
# ayarlar.sh — Merkezi yapılandırma. Tüm script'ler bunu source eder.
# Ortamına göre düzenle. Hiçbir sır (Ki/OPc) burada TUTULMAZ — onlar CLI'dan gelir.

# --- Host / Ağ ---
: "${HOST_IP:=192.168.23.6}"          # Open5GS host IP
: "${WEBUI_URL:=http://${HOST_IP}:9999}"
: "${WEBUI_USER:=admin}"
: "${WEBUI_PASS:=1423}"
: "${PYHSS_URL:=http://${HOST_IP}:8080}"

# --- PLMN ---
: "${MCC:=001}"
: "${MNC:=01}"
: "${IMS_DOMAIN:=ims.mnc${MNC}.mcc${MCC}.3gppnetwork.org}"
: "${SCSCF_HOST:=scscf.${IMS_DOMAIN}}"
: "${SCSCF_URI:=sip:${SCSCF_HOST}:6060}"

# --- Proje dizini (docker_open5gs) ---
# Kullanıcının gerçek yolu; tara_kur.sh otomatik bulmayı dener.
: "${OPEN5GS_DIR:=/home/mobsec/docker_open5gs}"

# --- Gerçek Sistem Dosya Yolları (PLMN/Servis) ---
: "${MME_CONF:=${OPEN5GS_DIR}/mme/mme.yaml}"
: "${ENB_CONF:=${OPEN5GS_DIR}/srslte/enb.conf}"
: "${ENB_RR_CONF:=${OPEN5GS_DIR}/srslte/rr.conf}"
: "${DNS_DIR:=${OPEN5GS_DIR}/dns}"
: "${ENV_FILE:=${OPEN5GS_DIR}/.env}"
: "${IMS_CONF_DIRS:=${OPEN5GS_DIR}/scscf ${OPEN5GS_DIR}/icscf ${OPEN5GS_DIR}/pcscf ${OPEN5GS_DIR}/pyhss}"

# --- Compose dosyaları ---
: "${IMS_COMPOSE:=4g-volte-deploy.yaml}"
: "${ENB_COMPOSE:=srsenb.yaml}"
: "${STACK_COMPOSE:=4g-volte-deploy.yaml}"

# --- Container İsimleri ---
: "${MONGO_CONTAINER:=mongo}"

# --- AUC varsayılanları ---
: "${DEFAULT_AMF:=8000}"
: "${DEFAULT_SQN:=0}"

# --- Renkli çıktı yardımcıları ---
c_ok()   { printf '\033[0;32m[✓]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[0;31m[✗]\033[0m %s\n' "$*" >&2; }
c_info() { printf '\033[0;36m[i]\033[0m %s\n' "$*"; }

# curl yoksa erken uyar
command -v curl >/dev/null 2>&1 || { c_err "curl gerekli ama bulunamadı"; }
command -v jq   >/dev/null 2>&1 || c_warn "jq yok — JSON ayrıştırma sınırlı olur (önerilir: apt install jq)"
