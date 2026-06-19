#!/usr/bin/env bash
# pyhss_api.sh — pyHSS REST API sarmalayıcı (IMS/VoLTE provisioning).
# DURUM.md §3'teki 5 adımı uygular. Fazla alan GÖNDERMEZ (400 item_id'den kaçınır).
# Kullanım: source ayarlar.sh && source pyhss_api.sh

# --- Düşük seviye PUT/GET ---
_pyhss_put() {
  # $1=endpoint (örn /apn/), $2=json gövde
  curl -sS -X PUT "${PYHSS_URL}$1" \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "$2"
}
_pyhss_get() {
  curl -sS -X GET "${PYHSS_URL}$1" -H 'accept: application/json'
}
_pyhss_delete() {
  curl -sS -X DELETE "${PYHSS_URL}$1" -H 'accept: application/json'
}

# JSON'dan tek alan çek (jq varsa jq, yoksa grep fallback)
_json_field() {
  # $1=json, $2=alan adı
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r ".$2 // empty"
  else
    printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9]*" | grep -o '[0-9]*$' | head -1
  fi
}

# --- pyHSS erişim kontrolü ---
pyhss_saglik() {
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' "${PYHSS_URL}/docs/" || echo 000)
  [ "$code" = "200" ] && { c_ok "pyHSS erişilebilir (${PYHSS_URL})"; return 0; }
  c_err "pyHSS erişilemiyor (${PYHSS_URL}) — HTTP $code"; return 1
}

# --- Adım 1: APN oluştur, apn_id döndür ---
pyhss_apn_ekle() {
  # $1=apn adı (internet|ims). stdout=apn_id
  local resp id
  resp=$(_pyhss_put "/apn/" "{\"apn\":\"$1\",\"apn_ambr_dl\":0,\"apn_ambr_ul\":0}")
  id=$(_json_field "$resp" "apn_id")
  if [ -z "$id" ]; then c_err "APN '$1' eklenemedi: $resp"; return 1; fi
  c_ok "APN '$1' -> apn_id=$id" >&2
  printf '%s' "$id"
}

# Mevcut APN'lerden ada göre apn_id bul (idempotent kurulum için)
pyhss_apn_id_bul() {
  # $1=apn adı. stdout=apn_id veya boş
  local list
  list=$(_pyhss_get "/apn/list" 2>/dev/null || _pyhss_get "/apn/")
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$list" | jq -r ".[] | select(.apn==\"$1\") | .apn_id" 2>/dev/null | head -1
  fi
}

# --- Adım 2: AUC oluştur, auc_id döndür ---
pyhss_auc_ekle() {
  # $1=imsi $2=ki $3=opc [$4=amf $5=sqn]. stdout=auc_id
  local imsi=$1 ki=$2 opc=$3 amf=${4:-$DEFAULT_AMF} sqn=${5:-$DEFAULT_SQN} resp id
  resp=$(_pyhss_put "/auc/" \
    "{\"ki\":\"$ki\",\"opc\":\"$opc\",\"amf\":\"$amf\",\"sqn\":$sqn,\"imsi\":\"$imsi\"}")
  id=$(_json_field "$resp" "auc_id")
  if [ -z "$id" ]; then c_err "AUC eklenemedi ($imsi): $resp"; return 1; fi
  c_ok "AUC ($imsi) -> auc_id=$id" >&2
  printf '%s' "$id"
}

# --- Adım 3: SUBSCRIBER oluştur ---
pyhss_subscriber_ekle() {
  # $1=imsi $2=auc_id $3=default_apn_id $4=apn_list(örn "2,3") $5=msisdn
  local imsi=$1 auc=$2 dapn=$3 alist=$4 msisdn=$5 resp id
  resp=$(_pyhss_put "/subscriber/" \
    "{\"imsi\":\"$imsi\",\"enabled\":true,\"auc_id\":$auc,\"default_apn\":$dapn,\"apn_list\":\"$alist\",\"msisdn\":\"$msisdn\",\"ue_ambr_dl\":0,\"ue_ambr_ul\":0}")
  id=$(_json_field "$resp" "subscriber_id")
  if [ -z "$id" ]; then c_err "Subscriber eklenemedi ($imsi): $resp"; return 1; fi
  c_ok "Subscriber ($imsi) -> subscriber_id=$id" >&2
  printf '%s' "$id"
}

# --- Adım 4: IMS_SUBSCRIBER oluştur (en kritik) ---
pyhss_ims_subscriber_ekle() {
  # $1=imsi $2=msisdn
  local imsi=$1 msisdn=$2 resp id
  resp=$(_pyhss_put "/ims_subscriber/" \
    "{\"imsi\":\"$imsi\",\"msisdn\":\"$msisdn\",\"sh_profile\":\"string\",\"scscf_peer\":\"${SCSCF_HOST}\",\"msisdn_list\":\"[$msisdn]\",\"ifc_path\":\"default_ifc.xml\",\"scscf\":\"${SCSCF_URI}\",\"scscf_realm\":\"${IMS_DOMAIN}\"}")
  id=$(_json_field "$resp" "ims_subscriber_id")
  if [ -z "$id" ]; then c_err "IMS subscriber eklenemedi ($imsi): $resp"; return 1; fi
  c_ok "IMS subscriber ($imsi) -> ims_subscriber_id=$id" >&2
  printf '%s' "$id"
}

# --- Üst seviye: APN'leri garanti et, internet+ims id'lerini "INTERNET_ID IMS_ID" döndür ---
pyhss_apnleri_garanti() {
  local iid mid
  iid=$(pyhss_apn_id_bul "internet"); [ -z "$iid" ] && iid=$(pyhss_apn_ekle "internet")
  mid=$(pyhss_apn_id_bul "ims");      [ -z "$mid" ] && mid=$(pyhss_apn_ekle "ims")
  printf '%s %s' "$iid" "$mid"
}

# --- Üst seviye: tek kartı tam IMS provision et ---
pyhss_kart_ekle() {
  # $1=imsi $2=ki $3=opc $4=msisdn  (APN'ler önceden garanti edilmiş olmalı)
  local imsi=$1 ki=$2 opc=$3 msisdn=$4
  read -r INTERNET_ID IMS_ID <<<"$(pyhss_apnleri_garanti)"
  local auc; auc=$(pyhss_auc_ekle "$imsi" "$ki" "$opc") || return 1
  pyhss_subscriber_ekle "$imsi" "$auc" "$INTERNET_ID" "${INTERNET_ID},${IMS_ID}" "$msisdn" >/dev/null || return 1
  pyhss_ims_subscriber_ekle "$imsi" "$msisdn" >/dev/null || return 1
  c_ok "Kart $imsi pyHSS IMS provisioning TAMAM (internet_apn=$INTERNET_ID ims_apn=$IMS_ID auc=$auc)"
}

# --- Üst seviye: pyHSS IMS kaydını sil ---
pyhss_kart_sil() {
  local imsi=$1
  c_info "pyHSS tarafında $imsi aranıyor (jq gerektirir)..."
  if ! command -v jq >/dev/null 2>&1; then
    c_warn "jq kurulu değil, pyHSS kayıtları otomatik silinemez."
    return 0
  fi

  local s_list s_id is_list is_id a_list a_id

  s_list=$(_pyhss_get "/subscriber/list" 2>/dev/null || _pyhss_get "/subscriber/")
  s_id=$(printf '%s' "$s_list" | jq -r ".[] | select(.imsi==\"$imsi\") | .subscriber_id" 2>/dev/null | head -1)
  if [ -n "$s_id" ]; then
    _pyhss_delete "/subscriber/$s_id" >/dev/null
    c_ok "pyHSS Subscriber silindi (id=$s_id)"
  fi

  is_list=$(_pyhss_get "/ims_subscriber/list" 2>/dev/null || _pyhss_get "/ims_subscriber/")
  is_id=$(printf '%s' "$is_list" | jq -r ".[] | select(.imsi==\"$imsi\") | .ims_subscriber_id" 2>/dev/null | head -1)
  if [ -n "$is_id" ]; then
    _pyhss_delete "/ims_subscriber/$is_id" >/dev/null
    c_ok "pyHSS IMS Subscriber silindi (id=$is_id)"
  fi

  a_list=$(_pyhss_get "/auc/list" 2>/dev/null || _pyhss_get "/auc/")
  a_id=$(printf '%s' "$a_list" | jq -r ".[] | select(.imsi==\"$imsi\") | .auc_id" 2>/dev/null | head -1)
  if [ -n "$a_id" ]; then
    _pyhss_delete "/auc/$a_id" >/dev/null
    c_ok "pyHSS AUC silindi (id=$a_id)"
  fi
}

