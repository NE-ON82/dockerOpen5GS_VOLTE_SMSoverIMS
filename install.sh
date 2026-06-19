#!/usr/bin/env bash
# install.sh — Sıfırdan VoLTE test ağı tam kurulum
# Kullanım: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPEN5GS_DIR="${SCRIPT_DIR}"

c_ok()   { printf '\033[0;32m[✓]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[0;31m[✗]\033[0m %s\n' "$*" >&2; }
c_info() { printf '\033[0;36m[i]\033[0m %s\n' "$*"; }

onay() { read -r -p "$1 [Enter=devam / Ctrl-C=iptal] "; }

echo "════════════════════════════════════════════════"
echo "  VoLTE Test Ağı — Sıfırdan Kurulum (install.sh)"
echo "════════════════════════════════════════════════"
echo "Proje Dizini: ${OPEN5GS_DIR}"
echo

# 1. Önkoşul kontrolü
c_info "1) Önkoşullar kontrol ediliyor..."
eksik=0
for cmd in docker "docker compose"; do
  if ! command -v $cmd >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    c_err "  $cmd kurulu değil."
    eksik=1
  else
    c_ok "  $cmd mevcut."
  fi
done

if ! command -v uhd_find_devices >/dev/null 2>&1; then
  c_warn "  uhd-host kurulu değil. B210 için gereklidir."
  c_info "  Kurmak için: sudo apt install -y uhd-host libuhd-dev"
  c_info "  Sonra firmware: sudo uhd_images_downloader"
  eksik=1
else
  c_ok "  uhd-host mevcut."
fi

if [ "$eksik" = 1 ]; then
  c_err "Önkoşullar eksik. Lütfen yukarıdaki paketleri kurup tekrar çalıştırın."
  exit 1
fi

# 2. xfrm kernel modülleri
c_info "2) xfrm (IPsec) modülleri yükleniyor (sudo gerekebilir)..."
echo "Çalıştırılıyor: sudo modprobe xfrm_user esp4 xfrm4_tunnel tunnel4 ah4"
sudo modprobe xfrm_user esp4 xfrm4_tunnel tunnel4 ah4 || {
  c_err "Modüller yüklenemedi. VoLTE IPsec (P-CSCF) çalışmayabilir."
  exit 1
}
lsmod | grep -q xfrm_user && c_ok "  xfrm modülleri başarıyla yüklendi." || c_warn "  xfrm modülleri lsmod'da görünmüyor."

# 3. .env hazırlığı
c_info "3) Çevre değişkenleri (.env) ayarlanıyor..."
if [ ! -f "${OPEN5GS_DIR}/.env" ]; then
  if [ -f "${OPEN5GS_DIR}/.env.example" ]; then
    cp "${OPEN5GS_DIR}/.env.example" "${OPEN5GS_DIR}/.env"
    c_ok "  .env.example dosyasından .env oluşturuldu."
  else
    c_err "  .env.example bulunamadı. Lütfen elle .env oluşturun."
    exit 1
  fi
else
  c_ok "  .env dosyası zaten mevcut."
fi

read -r -p "DOCKER_HOST_IP değerini girin (örn. 192.168.1.10) [Enter ile mevcut değeri koru]: " host_ip
if [ -n "$host_ip" ]; then
  sed -i "s/^HOST_IP=.*/HOST_IP=${host_ip}/" "${OPEN5GS_DIR}/.env"
  c_ok "  .env içindeki HOST_IP güncellendi: ${host_ip}"
fi

# 4. Docker container'larını başlat
c_info "4) EPC + IMS + HSS Yığını Başlatılıyor..."
if [ -f "${OPEN5GS_DIR}/4g-volte-deploy.yaml" ]; then
  ( cd "${OPEN5GS_DIR}" && sudo docker compose -f 4g-volte-deploy.yaml up -d )
  c_ok "  Container'lar başlatıldı. Hazır olmaları bekleniyor..."
  sleep 5
else
  c_err "  4g-volte-deploy.yaml bulunamadı!"
  exit 1
fi

# 5. Sağlık kontrolü
c_info "5) Sağlık kontrolü yapılıyor..."
calisanlar=$(sudo docker ps --format '{{.Names}}\t{{.Status}}' | grep "Up" || true)
beklenen_servisler="mme amf pcscf icscf scscf pyhss smsc upf"
for s in $beklenen_servisler; do
  if echo "$calisanlar" | grep -qi "$s"; then
    c_ok "  $s: Up"
  else
    c_warn "  $s: Bekleniyor veya çöktü"
  fi
done

# 6. B210/UHD doğrulaması
c_info "6) UHD / B210 Cihaz Doğrulaması..."
if uhd_find_devices >/dev/null 2>&1; then
  c_ok "  UHD cihazları bulundu. eNB yayınına hazır."
else
  c_warn "  UHD cihazı bulunamadı. USRP B210'un USB3 portuna takılı olduğundan emin olun."
fi

# 7. Sonuç
echo
echo "════════════════════════════════════════════════"
c_ok "Sistem kuruldu."
echo "Sonraki adım:"
echo "  1. Abone ekle : ./scripts/abone_ekle.sh --imsi <IMSI> --ki <KI> --opc <OPC> --msisdn <MSISDN>"
echo "  2. eNB başlat : ./scripts/volte start"
echo "  3. PLMN ayarla: ./scripts/plmn.sh (gerekirse)"
echo "════════════════════════════════════════════════"
