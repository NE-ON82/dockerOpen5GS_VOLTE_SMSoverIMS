#!/usr/bin/env bash
# plmn.sh — PLMN'i (MCC/MNC) tüm ilgili dosyalarda değiştirir.
# 'volte create plmn --mcc <MCC> --mnc <MNC>' bunu kullanır.
#
# ⚠️ ÖNEMLİ UYARILAR
#  - PLMN ÇOK yere dağılır: mme, enb.conf, DNS zone'ları, IMS domain'leri, .env.
#  - MNC HANE SAYISI kritik: 2 hane (01,11) ile 3 hane (110) domain'i değiştirir
#    (mnc01 vs mnc110). DNS, Diameter identity, IMS realm hepsi buna bağlıdır.
#  - SIM kart da aynı PLMN'e programlı olmalı — bu script SIM'i DEĞİŞTİREMEZ.
#  - Bu script değiştirdiği HER dosyanın yedeğini alır (PLMN_BACKUP_DIR).
#  - Dosya formatları docker_open5gs sürümüne göre değişebilir; script bulduğunu
#    değiştirir, bulamadığını atlar ve RAPOR eder. Sonrası ELLE doğrulanmalı.

# Eski PLMN'i bir dosyadan tahmin et (mme.yaml'dan mcc/mnc oku)
_mevcut_plmn_oku() {
  # stdout: "MCC MNC" (bulursa)
  local mcc mnc
  if [ -f "${MME_CONF}" ]; then
    mcc=$(grep -iE "mcc" "${MME_CONF}" | grep -oE "[0-9]{3}" | head -1)
    mnc=$(grep -iE "mnc" "${MME_CONF}" | grep -oE "[0-9]{2,3}" | head -1)
    [ -n "$mcc" ] && printf '%s %s' "$mcc" "$mnc"
  fi
}

# Yedek al
_plmn_yedekle() {
  # $1 = dosya yolu
  [ -f "$1" ] || return 0
  mkdir -p "${PLMN_BACKUP_DIR}"
  local rel; rel=$(echo "$1" | sed "s|${OPEN5GS_DIR}/||; s|/|__|g")
  cp -a "$1" "${PLMN_BACKUP_DIR}/${rel}.$(date +%Y%m%d-%H%M%S).bak"
}

# Bir dosyada eski->yeni mcc/mnc ve domain değişimini uygula
_dosyada_degistir() {
  # $1=dosya $2=eski_mcc $3=eski_mnc $4=yeni_mcc $5=yeni_mnc $6=dry_run
  local f="$1" omcc="$2" omnc="$3" nmcc="$4" nmnc="$5" dry="$6"
  [ -f "$f" ] || { c_warn "  atlandı (yok): $f"; return 0; }
  
  [ "$dry" != "1" ] && _plmn_yedekle "$f"

  local degisti=0
  local pad_omnc="${omnc}"
  [ "${#omnc}" -eq 2 ] && pad_omnc="0${omnc}"
  local pad_nmnc="${nmnc}"
  [ "${#nmnc}" -eq 2 ] && pad_nmnc="0${nmnc}"

  # 1) 3gppnetwork.org domain'leri (padded)
  if grep -q "mnc${pad_omnc}.mcc${omcc}" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i "s/mnc${pad_omnc}\.mcc${omcc}/mnc${pad_nmnc}.mcc${nmcc}/g" "$f"
  fi
  # 1.1) 3gppnetwork.org domain'leri (unpadded fallback)
  if grep -q "mnc${omnc}.mcc${omcc}" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i "s/mnc${omnc}\.mcc${omcc}/mnc${nmnc}.mcc${nmcc}/g" "$f"
  fi

  # 2) mme.yaml tarzı: mcc: <omcc> / mnc: <omnc>
  if grep -qiE "mcc:[[:space:]]*${omcc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(mcc:[[:space:]]*)${omcc}\b/\1${nmcc}/g" "$f"
  fi
  if grep -qiE "mnc:[[:space:]]*${omnc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(mnc:[[:space:]]*)${omnc}\b/\1${nmnc}/g" "$f"
  fi

  # 3) enb.conf tarzı: mcc = <omcc> / mnc = <omnc>
  if grep -qiE "mcc[[:space:]]*=[[:space:]]*${omcc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(mcc[[:space:]]*=[[:space:]]*)${omcc}\b/\1${nmcc}/g" "$f"
  fi
  if grep -qiE "mnc[[:space:]]*=[[:space:]]*${omnc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(mnc[[:space:]]*=[[:space:]]*)${omnc}\b/\1${nmnc}/g" "$f"
  fi

  # 4) .env tarzı: MCC=<omcc> / MNC=<omnc>
  if grep -qiE "^MCC=${omcc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/^(MCC=)${omcc}\b/\1${nmcc}/" "$f"
  fi
  if grep -qiE "^MNC=${omnc}\b" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/^(MNC=)${omnc}\b/\1${nmnc}/" "$f"
  fi

  # 5) scscf.cfg tarzı: #!define RO_MNC "02"
  if grep -qiE "define[[:space:]]+RO_MCC[[:space:]]+\"[0-9]+\"" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(define[[:space:]]+RO_MCC[[:space:]]+\")[0-9]+(\")/\1${nmcc}\2/g" "$f"
  fi
  if grep -qiE "define[[:space:]]+RO_MNC[[:space:]]+\"[0-9]+\"" "$f" 2>/dev/null; then
    degisti=1
    [ "$dry" != "1" ] && sed -i -E "s/(define[[:space:]]+RO_MNC[[:space:]]+\")[0-9]+(\")/\1${nmnc}\2/g" "$f"
  fi

  if [ "$degisti" = 1 ]; then
    if [ "$dry" = "1" ]; then c_info "  [DRY-RUN] Değişecek: $f"; else c_ok "  güncellendi: $f"; fi
  else
    if [ "$dry" != "1" ]; then c_warn "  PLMN izi bulunamadı: $f"; fi
  fi
}

plmn_create() {
  # $1=yeni_mcc $2=yeni_mnc $3=dry_run
  local nmcc="$1" nmnc="$2" dry_run="${3:-0}"

  # --- Doğrulama ---
  if ! echo "$nmcc" | grep -qE '^[0-9]{3}$'; then c_err "MCC 3 haneli olmalı (örn 001, 286)"; return 1; fi
  if ! echo "$nmnc" | grep -qE '^[0-9]{2,3}$'; then c_err "MNC 2 veya 3 haneli olmalı (örn 01, 11, 110)"; return 1; fi

  # Eski PLMN'i oku
  read -r omcc omnc <<<"$(_mevcut_plmn_oku)"
  if [ -z "${omcc:-}" ] || [ -z "${omnc:-}" ]; then
    c_warn "Mevcut PLMN otomatik okunamadı (${MME_CONF})."
    c_warn "Eski değerleri elle vermen gerek. Örnek:"
    c_warn "  OLD_MCC=001 OLD_MNC=01 volte create plmn --mcc ${nmcc} --mnc ${nmnc}"
    omcc="${OLD_MCC:-}"; omnc="${OLD_MNC:-}"
    [ -z "$omcc" ] || [ -z "$omnc" ] && { c_err "Eski PLMN belli değil, iptal."; return 1; }
  fi

  c_info "PLMN değişimi: ${omcc}/${omnc}  →  ${nmcc}/${nmnc}"

  # MNC hane sayısı uyarısı
  if [ "${#omnc}" != "${#nmnc}" ]; then
    c_warn "DİKKAT: MNC hane sayısı değişiyor (${#omnc} → ${#nmnc} hane)."
    c_warn "  Domain formatı değişir (mnc${omnc} → mnc${nmnc}). DNS/Diameter/IMS"
    c_warn "  identity'leri ELLE kontrol et."
  fi

  if [ "$dry_run" != "1" ]; then
    c_warn "Devam etmeden önce yığını durdurman önerilir: volte stop --all"
    printf "Devam edilsin mi? [e/H] "; read -r yanit
    case "$yanit" in e|E|evet|yes|y|Y) ;; *) c_info "İptal edildi."; return 0;; esac
    c_info "Yedekler: ${PLMN_BACKUP_DIR}"
  else
    c_info "=== DRY-RUN MODU (Sadece raporlanacak, değişiklik yapılmayacak) ==="
  fi

  # --- Dosyaları değiştir ---
  c_info "1) MME config..."
  _dosyada_degistir "${MME_CONF}" "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"

  c_info "2) eNB config..."
  _dosyada_degistir "${ENB_CONF}"    "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"
  _dosyada_degistir "${ENB_RR_CONF}" "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"

  c_info "3) .env..."
  _dosyada_degistir "${ENV_FILE}" "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"

  c_info "4) DNS zone dosyaları..."
  local pad_omnc="${omnc}"
  [ "${#omnc}" -eq 2 ] && pad_omnc="0${omnc}"
  if [ -d "${DNS_DIR}" ]; then
    while IFS= read -r df; do
      _dosyada_degistir "$df" "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"
    done < <(grep -rlE "mnc${pad_omnc}\.mcc${omcc}|mnc${omnc}\.mcc${omcc}|mcc${omcc}" "${DNS_DIR}" 2>/dev/null || true)
  else
    c_warn "  DNS dizini yok: ${DNS_DIR}"
  fi

  c_info "5) IMS / pyHSS config'leri (domain)..."
  for d in ${IMS_CONF_DIRS}; do
    [ -d "$d" ] || { c_warn "  yok: $d"; continue; }
    while IFS= read -r cf; do
      _dosyada_degistir "$cf" "$omcc" "$omnc" "$nmcc" "$nmnc" "$dry_run"
    done < <(grep -rlE "mnc${pad_omnc}\.mcc${omcc}|mnc${omnc}\.mcc${omcc}|RO_MCC" "$d" 2>/dev/null || true)
  done

  echo
  if [ "$dry_run" = "1" ]; then
    c_ok "DRY-RUN tamamlandı. Yukarıdaki dosyalar DEĞİŞTİRİLECEK."
    c_info "Gerçekten uygulamak için --dry-run bayrağını kaldırın."
  else
    c_ok "PLMN değişimi uygulandı: ${nmcc}/${nmnc}"
    c_warn "SONRAKİ ADIMLAR (ELLE):"
    echo "  1. Yedekler: ${PLMN_BACKUP_DIR} (sorun olursa geri al)"
    echo "  2. Diameter (freeDiameter) identity/sertifikaları domain'e bağlıysa yeniden üret."
    echo "  3. SIM kartları yeni PLMN'e (${nmcc}/${nmnc}) programla — yoksa attach OLMAZ."
    echo "  4. Aboneleri yeni IMS domain'iyle pyHSS'e tekrar gir (scscf realm değişti)."
    echo "  5. Yığını yeniden başlat: volte start"
    echo "  6. S1 Setup ve attach'i izle: sudo docker logs -f mme | grep -iE 'S1|PLMN|Attach'"
    c_warn "  ayarlar.sh içindeki IMS_DOMAIN/SCSCF değerlerini de güncelle (MNC/MCC)."
  fi
}
