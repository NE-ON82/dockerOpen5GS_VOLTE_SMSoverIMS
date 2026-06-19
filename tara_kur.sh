#!/usr/bin/env bash
# tara_kur.sh — MEVCUT bir Open5GS kurulumuna VoLTE+SMS yapılandırmasını ekler.
# Zaten var olan /home/mobsec/docker_open5gs dizinini hedefler ve bizim
# kanıtlanmış configlerimizi (default_ifc.xml, scscf.cfg, smsc, vb.) oraya kopyalar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPEN5GS_DIR_DEFAULT="/home/mobsec/docker_open5gs"

c_ok()   { printf '\033[0;32m[✓]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[0;31m[✗]\033[0m %s\n' "$*" >&2; }
c_info() { printf '\033[0;36m[i]\033[0m %s\n' "$*"; }

onay() {
  local prompt="$1"
  local ans
  read -r -p "$prompt [e/H] " ans
  case "$ans" in
    [eE]|[yY]|[eE][vV][eE][tT]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

echo "════════════════════════════════════════════════"
echo "  tara_kur.sh — Mevcut Open5GS'e VoLTE+SMS Ekle"
echo "════════════════════════════════════════════════"

# 1. Mevcut Open5GS dizinini bul/sor
read -r -p "Mevcut Open5GS dizini [${OPEN5GS_DIR_DEFAULT}]: " open5gs_input
TARGET_DIR="${open5gs_input:-${OPEN5GS_DIR_DEFAULT}}"

if [ ! -d "${TARGET_DIR}" ]; then
  c_err "HATA: ${TARGET_DIR} dizini bulunamadı!"
  exit 1
fi
c_ok "Hedef dizin: ${TARGET_DIR}"

# 2. IMS bileşenlerini tara
c_info "1) IMS Bileşenleri Taranıyor..."
ims_bileşenleri="pcscf icscf scscf pyhss smsc rtpengine"
eksik_bilesen=""
for bilesen in $ims_bileşenleri; do
  if [ ! -d "${TARGET_DIR}/${bilesen}" ]; then
    c_warn "  ${bilesen} dizini YOK"
    eksik_bilesen="${eksik_bilesen} ${bilesen}"
  else
    c_ok "  ${bilesen} dizini mevcut"
  fi
done

if [ -n "$eksik_bilesen" ]; then
  c_warn "Bazı IMS bileşenleri (dizinleri) eksik. Hedef repoda VoLTE altyapısı olmayabilir!"
  if ! onay "Yine de devam etmek istiyor musunuz?"; then
    echo "İptal edildi."
    exit 1
  fi
fi

# 3. xfrm kernel modüllerini tara
c_info "2) xfrm Kernel Modülleri Taranıyor..."
if lsmod | grep -q xfrm_user; then
  c_ok "  xfrm modülleri yüklü"
else
  c_warn "  xfrm modülleri yüklü değil. IPsec için zorunlu."
  if onay "Yüklemek ister misiniz (sudo gerektirir)?"; then
    sudo modprobe xfrm_user esp4 xfrm4_tunnel tunnel4 ah4
    lsmod | grep -q xfrm_user && c_ok "  Yüklendi." || c_err "  Yüklenemedi."
  fi
fi

# 4. Config Dosyalarını Kopyalama Öncesi Kontrol ve Yedekleme
c_info "3) Eksik/Hatalı Config'leri Kapatma ve Kopyalama..."
YEDEK_DIR="${TARGET_DIR}/yedek_$(date +%Y%m%d_%H%M%S)"

kopyala_ve_yedekle() {
  local kaynak="$1"
  local hedef="$2"
  
  if [ ! -f "${kaynak}" ]; then
    c_warn "  Kaynak dosya ${kaynak} bulunamadı (bizim repoda eksik). Atlanıyor."
    return
  fi

  if [ -f "${hedef}" ]; then
    mkdir -p "${YEDEK_DIR}"
    local rel_yol
    rel_yol=$(realpath --relative-to="${TARGET_DIR}" "${hedef}" | sed 's|/|_|g')
    cp "${hedef}" "${YEDEK_DIR}/${rel_yol}.bak"
    c_info "  Yedeklendi: ${hedef} -> ${YEDEK_DIR}/${rel_yol}.bak"
  fi

  cp "${kaynak}" "${hedef}"
  c_ok "  Kopyalandı: ${hedef}"
}

if onay "Çalışan config dosyalarımız (default_ifc.xml, scscf.cfg, smsc.cfg vb.) hedef dizine kopyalansın mı?"; then
  # default_ifc.xml (REGISTER trigger için zorunlu)
  kopyala_ve_yedekle "${SCRIPT_DIR}/pyhss/default_ifc.xml" "${TARGET_DIR}/pyhss/default_ifc.xml"
  
  # scscf.cfg
  kopyala_ve_yedekle "${SCRIPT_DIR}/scscf/scscf.cfg" "${TARGET_DIR}/scscf/scscf.cfg"
  
  # smsc config
  kopyala_ve_yedekle "${SCRIPT_DIR}/smsc/smsc.cfg" "${TARGET_DIR}/smsc/smsc.cfg"
  kopyala_ve_yedekle "${SCRIPT_DIR}/smsc/kamailio_smsc.cfg" "${TARGET_DIR}/smsc/kamailio_smsc.cfg"

  # pyhss config
  kopyala_ve_yedekle "${SCRIPT_DIR}/pyhss/config.yaml" "${TARGET_DIR}/pyhss/config.yaml"
  
  c_ok "Tüm dosyalar kopyalandı."
else
  c_info "Kopyalama işlemi atlandı."
fi

# 5. Özet
echo
echo "════════════════════════════════════════════════"
c_ok "Tara ve Kur İşlemi Tamamlandı."
echo "Sonraki Adımlar:"
echo "  1. Yığını yeniden başlatın: docker compose ... down && up -d"
echo "  2. SMS ve VoLTE çağrısı için cihazları test edin."
echo "  3. Bir sorun olursa, alınan yedekler: ${YEDEK_DIR}"
echo "════════════════════════════════════════════════"
