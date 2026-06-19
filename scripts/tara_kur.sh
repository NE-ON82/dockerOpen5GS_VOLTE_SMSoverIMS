#!/usr/bin/env bash
# tara_kur.sh — MEVCUT bir 4G (internet çıkabilen) Open5GS kurulumunu tarar ve
# VoLTE için eksik olan parçaları ekler. Mevcut yapıyı bozmaz; idempotenttir.
#
# Yaptığı kontroller / eklemeler:
#   1. Proje dizinini ve compose dosyalarını bul
#   2. IMS container'ları (pcscf/icscf/scscf/pyhss/rtpengine) çalışıyor mu? Değilse başlat.
#   3. Host xfrm modülleri yüklü mü? Değilse yükle (sudo).
#   4. P-CSCF privileged/NET_ADMIN var mı? (uyarı)
#   5. pyHSS erişilebilir mi? APN'ler (internet/ims) var mı? Yoksa ekle.
#   6. Özet + sonraki adımlar.
#
# Abone provisioning'i bu script YAPMAZ (kart bilgisi gerekir) — onu ./volte yapar.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ayarlar.sh"
source "${SCRIPT_DIR}/lib/pyhss_api.sh"

echo "════════════════════════════════════════════════"
echo "  tara_kur.sh — Mevcut 4G yapıyı VoLTE'ye yükselt"
echo "════════════════════════════════════════════════"

# --- 1. Proje dizini ---
c_info "1) Open5GS proje dizini aranıyor..."
if [ ! -f "${OPEN5GS_DIR}/${IMS_COMPOSE}" ]; then
  found=$(find "$HOME" /opt /srv -maxdepth 4 -name "${IMS_COMPOSE}" 2>/dev/null | head -1 || true)
  if [ -n "$found" ]; then
    OPEN5GS_DIR="$(dirname "$found")"
  fi
fi
if [ -f "${OPEN5GS_DIR}/${IMS_COMPOSE}" ]; then
  c_ok "Proje dizini: ${OPEN5GS_DIR}"
else
  c_err "IMS compose (${IMS_COMPOSE}) bulunamadı. OPEN5GS_DIR'i ayarlar.sh'de elle ayarla."
  c_warn "Devam ediliyor (bazı adımlar atlanabilir)."
fi

# --- 2. IMS container'ları ---
c_info "2) IMS bileşenleri kontrol ediliyor..."
ims_servisler="pcscf icscf scscf pyhss rtpengine"
calisanlar=$(sudo docker ps --format '{{.Names}}' 2>/dev/null || true)
eksik_ims=""
for s in $ims_servisler; do
  if echo "$calisanlar" | grep -qx "$s"; then
    c_ok "  $s çalışıyor"
  else
    c_warn "  $s YOK"
    eksik_ims="${eksik_ims} $s"
  fi
done
if [ -n "$eksik_ims" ]; then
  if [ -f "${OPEN5GS_DIR}/${IMS_COMPOSE}" ]; then
    c_info "  Eksik IMS bileşenleri için ${IMS_COMPOSE} başlatılıyor..."
    ( cd "${OPEN5GS_DIR}" && sudo docker compose -f "${IMS_COMPOSE}" up -d )
    c_ok "  IMS yığını başlatıldı (birkaç saniye bekle)."
  else
    c_err "  IMS başlatılamıyor: compose dosyası yok."
  fi
fi

# --- 3. xfrm modülleri ---
c_info "3) Host xfrm (IPsec) modülleri kontrol ediliyor..."
if lsmod | grep -q xfrm_user; then
  c_ok "  xfrm modülleri yüklü"
else
  c_warn "  xfrm modülleri yüklü değil — yükleniyor (sudo)..."
  sudo modprobe xfrm_user esp4 xfrm4_tunnel tunnel4 ah4
  lsmod | grep -q xfrm_user && c_ok "  xfrm yüklendi" || c_err "  xfrm yüklenemedi"
fi
if sudo ip xfrm state >/dev/null 2>&1; then
  c_ok "  ip xfrm state çalışıyor (host IPsec hazır)"
else
  c_warn "  ip xfrm state çalışmadı — kernel xfrm desteğini kontrol et"
fi

# --- 4. P-CSCF yetki kontrolü (bilgi) ---
c_info "4) P-CSCF IPsec yetkileri (bilgi)..."
if [ -f "${OPEN5GS_DIR}/${IMS_COMPOSE}" ]; then
  if grep -A15 'pcscf:' "${OPEN5GS_DIR}/${IMS_COMPOSE}" | grep -q 'NET_ADMIN'; then
    c_ok "  pcscf: cap_add NET_ADMIN var"
  else
    c_warn "  pcscf'te NET_ADMIN görünmüyor — IPsec için gerekebilir (privileged:true de olur)"
  fi
fi

# --- 5. pyHSS + APN'ler ---
c_info "5) pyHSS ve IMS APN'leri kontrol ediliyor..."
if pyhss_saglik; then
  read -r INTERNET_ID IMS_ID <<<"$(pyhss_apnleri_garanti)"
  if [ -n "${INTERNET_ID}" ] && [ -n "${IMS_ID}" ]; then
    c_ok "  pyHSS APN'leri hazır: internet=${INTERNET_ID}, ims=${IMS_ID}"
  else
    c_warn "  APN id'leri okunamadı (jq yoksa olabilir). Swagger'dan kontrol et."
  fi
else
  c_err "  pyHSS erişilemiyor — IMS provisioning yapılamaz. Container'ı kontrol et."
fi

# --- Özet ---
echo
echo "════════════════════════════════════════════════"
c_ok "Tarama tamamlandı."
echo "Sonraki adımlar:"
echo "  • Aboneleri ekle (EPC zaten varsa pyHSS'i de ekler):"
echo "      ./volte add subscriber --imsi <I> --ki <K> --opc <O> --msisdn <M>"
echo "  • Telefonda VoLTE aç: docs/04_TELEFON_VOLTE.md"
echo "  • Doğrula: ./volte check --imsi <I>"
echo "════════════════════════════════════════════════"
