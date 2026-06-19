#!/usr/bin/env bash
# abone_ekle.sh — EPC ve IMS (pyHSS) için tek komutla abone ekler.
# Kullanım: ./abone_ekle.sh --imsi X --ki Y --opc Z --msisdn M

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ayarlar.sh"
source "${SCRIPT_DIR}/lib/pyhss_api.sh"
source "${SCRIPT_DIR}/lib/webui_api.sh"

ARG_IMSI=""; ARG_KI=""; ARG_OPC=""; ARG_MSISDN=""; ARG_AMF=""; ARG_SQN=""

kullanim() {
  cat <<EOF
abone_ekle.sh — VoLTE abone yönetimi (EPC + IMS)

Kullanım:
  ./abone_ekle.sh --imsi <IMSI> --ki <KI> --opc <OPC> --msisdn <MSISDN> [--amf <AMF>] [--sqn <SQN>]

Örnek:
  ./abone_ekle.sh --imsi 001010000000001 \\
    --ki <KART_KI_DEGERI> \\
    --opc <KART_OPC_DEGERI> \\
    --msisdn 0010000000001
EOF
}

_parse_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --imsi)   ARG_IMSI="$2"; shift 2;;
      --ki)     ARG_KI="$2"; shift 2;;
      --opc)    ARG_OPC="$2"; shift 2;;
      --msisdn) ARG_MSISDN="$2"; shift 2;;
      --amf)    ARG_AMF="$2"; shift 2;;
      --sqn)    ARG_SQN="$2"; shift 2;;
      -h|--help) kullanim; exit 0;;
      *) c_err "Bilinmeyen argüman: $1"; return 1;;
    esac
  done
}

_gerekli() {
  local eksik=0
  for v in "$@"; do
    case "$v" in
      imsi)   [ -z "$ARG_IMSI" ]   && { c_err "--imsi gerekli"; eksik=1; };;
      ki)     [ -z "$ARG_KI" ]     && { c_err "--ki gerekli"; eksik=1; };;
      opc)    [ -z "$ARG_OPC" ]    && { c_err "--opc gerekli"; eksik=1; };;
      msisdn) [ -z "$ARG_MSISDN" ] && { c_err "--msisdn gerekli"; eksik=1; };;
    esac
  done
  [ "$eksik" = 0 ]
}

main() {
  if [ $# -eq 0 ]; then
    kullanim
    exit 0
  fi

  _parse_flags "$@" || exit 1
  _gerekli imsi ki opc msisdn || exit 1
  [ -n "$ARG_AMF" ] && DEFAULT_AMF="$ARG_AMF"
  [ -n "$ARG_SQN" ] && DEFAULT_SQN="$ARG_SQN"

  c_info "Abone ekleniyor: ${ARG_IMSI} (MSISDN ${ARG_MSISDN})"

  c_info "1/2 — EPC (open5gs / MongoDB)..."
  webui_saglik || exit 1
  webui_abone_ekle "$ARG_IMSI" "$ARG_KI" "$ARG_OPC" "$ARG_MSISDN" || exit 1

  c_info "2/2 — IMS (pyHSS)..."
  pyhss_saglik || exit 1
  pyhss_kart_ekle "$ARG_IMSI" "$ARG_KI" "$ARG_OPC" "$ARG_MSISDN" || exit 1

  c_ok "Abone ${ARG_IMSI} hem EPC hem IMS'e eklendi."
  c_info "Telefonu uçak modu aç-kapa yapıp durumu kontrol edebilirsiniz."
}

main "$@"
