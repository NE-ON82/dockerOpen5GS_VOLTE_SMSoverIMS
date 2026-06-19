#!/usr/bin/env bash
# servis.sh — VoLTE yığınını (EPC+IMS) ve eNB yayınını yönetir.
# 'volte start/stop/status/restart' bunları kullanır.
#
# Tasarım:
#   - EPC+IMS çekirdeği: PC kapansa/yeniden başlasa da ayakta kalmalı.
#     Bunu 'restart: unless-stopped' politikası sağlar (volte enable-boot ile eklenir).
#   - eNB (yayın): RF açıp kapatmak istersin → start/stop eNB'yi yönetir.
#
# Kullanım (CLI üzerinden):
#   volte start            → çekirdek (yoksa) + eNB başlat
#   volte stop             → sadece eNB'yi durdur (yayını kes, çekirdek ayakta)
#   volte stop --all       → her şeyi durdur (çekirdek dahil)
#   volte status           → ne çalışıyor
#   volte restart          → eNB'yi yeniden başlat
#   volte enable-boot      → çekirdek container'larına restart:unless-stopped ekle

_compose() {
  # compose dosyasında docker compose çalıştırır. $1=dosya, gerisi=komut
  local file="$1"; shift
  ( cd "${OPEN5GS_DIR}" && sudo docker compose -f "${file}" "$@" )
}

_calisan_container() {
  sudo docker ps --format '{{.Names}}' 2>/dev/null
}

# --- Çekirdek (EPC+IMS) çalışıyor mu? (mme'yi gösterge al) ---
cekirdek_calisiyor_mu() {
  _calisan_container | grep -qx "mme"
}

# --- eNB çalışıyor mu? ---
enb_calisiyor_mu() {
  _calisan_container | grep -qx "srsenb"
}

servis_start() {
  c_info "VoLTE yığını başlatılıyor..."

  # 1. Çekirdek (EPC+IMS) — yoksa kaldır
  if cekirdek_calisiyor_mu; then
    c_ok "Çekirdek (EPC+IMS) zaten çalışıyor"
  else
    if [ -f "${OPEN5GS_DIR}/${STACK_COMPOSE}" ]; then
      c_info "Çekirdek başlatılıyor (${STACK_COMPOSE})..."
      _compose "${STACK_COMPOSE}" up -d
      sleep 4
      cekirdek_calisiyor_mu && c_ok "Çekirdek ayakta" || c_warn "Çekirdek doğrulanamadı"
    else
      c_err "${STACK_COMPOSE} bulunamadı (${OPEN5GS_DIR})"; return 1
    fi
  fi

  # 2. eNB (yayın)
  if enb_calisiyor_mu; then
    c_ok "eNB zaten yayında"
  else
    if [ -f "${OPEN5GS_DIR}/${ENB_COMPOSE}" ]; then
      c_info "eNB başlatılıyor (${ENB_COMPOSE})..."
      _compose "${ENB_COMPOSE}" up -d
      sleep 2
      enb_calisiyor_mu && c_ok "eNB yayında" || c_warn "eNB doğrulanamadı (USRP/UHD?)"
    else
      c_err "${ENB_COMPOSE} bulunamadı"; return 1
    fi
  fi

  c_ok "Başlatma tamam. Log: sudo docker logs -f srsenb"
}

servis_stop() {
  local hepsi="${1:-}"
  if [ "$hepsi" = "--all" ]; then
    c_warn "TÜM yığın durduruluyor (çekirdek + eNB)..."
    [ -f "${OPEN5GS_DIR}/${ENB_COMPOSE}" ]   && _compose "${ENB_COMPOSE}" down
    [ -f "${OPEN5GS_DIR}/${STACK_COMPOSE}" ] && _compose "${STACK_COMPOSE}" down
    c_ok "Her şey durduruldu."
  else
    c_info "Sadece eNB (yayın) durduruluyor; çekirdek ayakta kalır..."
    if [ -f "${OPEN5GS_DIR}/${ENB_COMPOSE}" ]; then
      _compose "${ENB_COMPOSE}" down
      c_ok "eNB durduruldu (yayın kapalı). Çekirdek hâlâ çalışıyor."
      c_info "Her şeyi durdurmak için: volte stop --all"
    fi
  fi
}

servis_restart() {
  c_info "eNB yeniden başlatılıyor..."
  [ -f "${OPEN5GS_DIR}/${ENB_COMPOSE}" ] && { _compose "${ENB_COMPOSE}" down; sleep 1; _compose "${ENB_COMPOSE}" up -d; }
  enb_calisiyor_mu && c_ok "eNB yeniden yayında" || c_warn "eNB doğrulanamadı"
}

servis_status() {
  echo "════════ VoLTE Yığın Durumu ════════"
  if cekirdek_calisiyor_mu; then c_ok "Çekirdek (EPC+IMS): ÇALIŞIYOR"; else c_warn "Çekirdek: KAPALI"; fi
  if enb_calisiyor_mu;     then c_ok "eNB (yayın): AÇIK";          else c_warn "eNB: KAPALI"; fi
  echo "────────────────────────────────────"
  sudo docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | \
    grep -iE "NAME|mme|hss|pcscf|icscf|scscf|pyhss|rtpengine|mongo|sgw|smf|upf|pgw|srsenb" || true
}

# --- Kalıcılık: restart politikası ---
# PC reboot sonrası container'lar kendiliğinden gelsin diye 'unless-stopped' ekler.
# Compose dosyalarındaki her servise restart politikası eklemek yerine, çalışan
# container'lara docker update ile uygular (en güvenli, dosyaya dokunmaz).
servis_enable_boot() {
  c_info "Çalışan container'lara restart=unless-stopped uygulanıyor..."
  local names; names=$(_calisan_container)
  if [ -z "$names" ]; then c_warn "Çalışan container yok; önce 'volte start'."; return 1; fi
  local n
  for n in $names; do
    sudo docker update --restart unless-stopped "$n" >/dev/null 2>&1 \
      && c_ok "  $n → unless-stopped" || c_warn "  $n güncellenemedi"
  done
  c_ok "Tamam. Artık PC yeniden başlasa da bu container'lar kendiliğinden gelir."
  c_info "Docker servisi de boot'ta açık olmalı: sudo systemctl enable docker"
  c_warn "NOT: eNB'yi (srsenb) boot'ta otomatik AÇMAK genelde istenmez (USRP/RF)."
  c_warn "     eNB için restart eklemek istersen: sudo docker update --restart unless-stopped srsenb"
}

servis_disable_boot() {
  c_info "restart politikası 'no'ya çekiliyor (çalışanlar için)..."
  local n
  for n in $(_calisan_container); do
    sudo docker update --restart no "$n" >/dev/null 2>&1 && c_ok "  $n → no"
  done
}
