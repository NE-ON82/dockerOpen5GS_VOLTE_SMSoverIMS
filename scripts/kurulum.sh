#!/usr/bin/env bash
# kurulum.sh — Sıfırdan VoLTE test ağı kurulum orkestrasyonu.
# Adımları sırayla yürütür; donanım/sudo gerektiren kısımlarda kullanıcıyı yönlendirir.
# Zaten 4G'si olan için: bunun yerine ./tara_kur.sh kullan.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ayarlar.sh"

echo "════════════════════════════════════════════════"
echo "  VoLTE Test Ağı — Sıfırdan Kurulum"
echo "════════════════════════════════════════════════"
echo "Host IP : ${HOST_IP}"
echo "PLMN    : MCC=${MCC} MNC=${MNC}"
echo "Proje   : ${OPEN5GS_DIR}"
echo

onay() { read -r -p "$1 [Enter=devam / Ctrl-C=iptal] "; }

# --- 0. Önkoşul kontrol ---
c_info "0) Önkoşullar kontrol ediliyor..."
for t in docker curl; do
  command -v "$t" >/dev/null 2>&1 && c_ok "  $t var" || c_err "  $t YOK (gerekli)"
done
command -v docker >/dev/null 2>&1 && {
  docker compose version >/dev/null 2>&1 && c_ok "  docker compose var" \
    || c_warn "  docker compose bulunamadı (eski 'docker-compose' olabilir)"
}

# --- 1. UHD / B210 (donanım — kullanıcı) ---
c_info "1) UHD / B210 (donanım adımı — sen çalıştır)"
cat <<EOF
   sudo apt install -y uhd-host libuhd-dev
   sudo uhd_images_downloader
   uhd_usrp_probe   # 'Operating over USB 3' + 'Register loopback test passed' görmeli
EOF
onay "B210 hazır olduğunda devam et."

# --- 2. docker_open5gs ---
c_info "2) docker_open5gs"
if [ ! -d "${OPEN5GS_DIR}" ]; then
  c_warn "  ${OPEN5GS_DIR} yok. Klonlamak için:"
  echo "    git clone https://github.com/herlesupreeth/docker_open5gs ${OPEN5GS_DIR}"
  echo "    cd ${OPEN5GS_DIR} && git checkout master && cp .env.example .env"
  echo "    (.env içinde HOST IP / DNS ayarla)"
  onay "Klonlayıp .env'i ayarladıktan sonra devam et."
else
  c_ok "  ${OPEN5GS_DIR} mevcut"
fi

# --- 3. EPC + IMS başlat ---
c_info "3) EPC + IMS yığını başlatılıyor (${IMS_COMPOSE})"
if [ -f "${OPEN5GS_DIR}/${IMS_COMPOSE}" ]; then
  onay "  '${OPEN5GS_DIR}' içinde compose up çalıştırılacak."
  ( cd "${OPEN5GS_DIR}" && sudo docker compose -f "${IMS_COMPOSE}" up -d )
  sleep 5
  sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
else
  c_err "  ${IMS_COMPOSE} bulunamadı; OPEN5GS_DIR'i kontrol et."
fi

# --- 4. xfrm modülleri ---
c_info "4) xfrm (IPsec) modülleri yükleniyor..."
sudo modprobe xfrm_user esp4 xfrm4_tunnel tunnel4 ah4
lsmod | grep -q xfrm_user && c_ok "  xfrm yüklü" || c_warn "  xfrm yüklenemedi"

# --- 5. SIM (kullanıcı) ---
c_info "5) SIM programlama (sen yap) — docs/02_SIM_PROGRAMLAMA.md"
echo "   PLMN ${MCC}/${MNC}, Type=OPc, SQN check KAPALI."
onay "SIM'ler programlandıysa devam et."

# --- 6. Abone ekle ---
c_info "6) Abone ekleme"
echo "   ./volte add subscriber --imsi <I> --ki <K> --opc <O> --msisdn <M>"
echo "   (her kart için tekrarla)"

# --- 7. eNB (kullanıcı) ---
c_info "7) eNB başlat (sen yap)"
echo "   cd ${OPEN5GS_DIR} && sudo docker compose -f ${ENB_COMPOSE} up -d"
echo "   sudo docker container attach srsenb"

echo
c_ok "Kurulum orkestrasyonu bitti."
echo "Telefon: docs/04_TELEFON_VOLTE.md • Çağrı: docs/05_VOLTE_CAGRI.md"
echo "Doğrula: ./volte check --imsi <IMSI>"
