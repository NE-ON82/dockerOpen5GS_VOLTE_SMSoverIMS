#!/usr/bin/env bash
# webui_api.sh — open5gs EPC abonesini doğrudan MongoDB'ye yazar (WebUI ile aynı yer).
# Tam VoLTE APN yapısını kurar (DURUM.md §5): internet(QCI9) + ims(QCI5/1/2), IPv4, GBR/MBR 128/128.
# WebUI REST'ine veya open5gs-dbctl'e bağımlı değildir (ikisi de APN'i eksik kurar).
#
# Gereksinim: mongo CLI host'ta veya mongo container'ında erişilebilir olmalı.
# Çoğu docker_open5gs kurulumunda 'mongo' adında bir container vardır.
#
# Kullanım: source ayarlar.sh && source webui_api.sh

# Mongo komutunu çalıştır: önce host mongosh/mongo, olmazsa mongo container exec
: "${MONGO_CONTAINER:=mongo}"
: "${MONGO_DB:=open5gs}"

_mongo_eval() {
  # $1 = JS ifadesi. open5gs DB context'inde çalıştırır.
  local js="$1"
  if command -v mongosh >/dev/null 2>&1; then
    mongosh --quiet "${MONGO_DB}" --eval "$js"
  elif command -v mongo >/dev/null 2>&1; then
    mongo --quiet "${MONGO_DB}" --eval "$js"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${MONGO_CONTAINER}"; then
    # container içinde mongosh varsa onu, yoksa mongo'yu dene
    if docker exec "${MONGO_CONTAINER}" sh -c 'command -v mongosh >/dev/null 2>&1'; then
      docker exec "${MONGO_CONTAINER}" mongosh --quiet "${MONGO_DB}" --eval "$js"
    else
      docker exec "${MONGO_CONTAINER}" mongo --quiet "${MONGO_DB}" --eval "$js"
    fi
  else
    c_err "mongo/mongosh bulunamadı (host'ta da '${MONGO_CONTAINER}' container'ında da)"; return 1
  fi
}

webui_saglik() {
  if _mongo_eval 'db.subscribers.countDocuments({})' >/dev/null 2>&1; then
    c_ok "MongoDB erişilebilir (db=${MONGO_DB})"; return 0
  fi
  c_err "MongoDB erişilemiyor — MONGO_CONTAINER='${MONGO_CONTAINER}' doğru mu?"; return 1
}

# Aboneyi tam VoLTE APN yapısıyla ekle/güncelle (idempotent: varsa değiştirir).
# Şema open5gs WebUI'nin yazdığı yapıyla birebir: slice[].session[] altında her APN.
# QCI/ARP/AMBR değerleri DURUM.md §5 ile aynı. AMBR bytes cinsinden.
webui_abone_ekle() {
  # $1=imsi $2=ki $3=opc $4=msisdn [$5=amf $6=sqn]
  local imsi=$1 ki=$2 opc=$3 msisdn=$4 amf=${5:-$DEFAULT_AMF} sqn=${6:-$DEFAULT_SQN}

  # JS: önce sil (idempotent), sonra tam dokümanı ekle.
  # AMBR: internet 1Gbps=1000000000; ims downlink 3850 Kbps ul 1530 Kbps (Kbps->bps).
  # QCI1/2: GBR/MBR 128 Kbps = 128000 bps.
  local js
  js=$(cat <<JS
db.subscribers.deleteOne({ imsi: "${imsi}" });
db.subscribers.insertOne({
  imsi: "${imsi}",
  msisdn: [ "${msisdn}" ],
  mme_host: [], mme_realm: [],
  purge_flag: [],
  security: {
    k:   "${ki}",
    opc: "${opc}",
    amf: "${amf}",
    op:  null,
    sqn: NumberLong(${sqn})
  },
  ambr: { downlink: { value: 1, unit: 3 }, uplink: { value: 1, unit: 3 } },
  slice: [{
    sst: 1, default_indicator: true,
    session: [
      {
        name: "internet",
        type: 1,
        qos: { index: 9, arp: { priority_level: 8,
          pre_emption_capability: 1, pre_emption_vulnerability: 1 } },
        ambr: { downlink: { value: 1, unit: 3 }, uplink: { value: 1, unit: 3 } }
      },
      {
        name: "ims",
        type: 1,
        qos: { index: 5, arp: { priority_level: 1,
          pre_emption_capability: 1, pre_emption_vulnerability: 1 } },
        ambr: { downlink: { value: 3850, unit: 1 }, uplink: { value: 1530, unit: 1 } }
      },
      {
        name: "ims",
        type: 1,
        qos: { index: 1, arp: { priority_level: 2,
          pre_emption_capability: 1, pre_emption_vulnerability: 1 } },
        ambr: { downlink: { value: 128, unit: 1 }, uplink: { value: 128, unit: 1 } },
        gbr:  { downlink: { value: 128, unit: 1 }, uplink: { value: 128, unit: 1 } }
      },
      {
        name: "ims",
        type: 1,
        qos: { index: 2, arp: { priority_level: 4,
          pre_emption_capability: 1, pre_emption_vulnerability: 1 } },
        ambr: { downlink: { value: 128, unit: 1 }, uplink: { value: 128, unit: 1 } },
        gbr:  { downlink: { value: 128, unit: 1 }, uplink: { value: 128, unit: 1 } }
      }
    ]
  }],
  __v: 0
});
print("inserted:" + "${imsi}");
JS
)
  if _mongo_eval "$js" | grep -q "inserted:${imsi}"; then
    c_ok "EPC abonesi MongoDB'ye yazıldı (tam VoLTE APN): ${imsi}"
  else
    c_err "EPC abonesi yazılamadı: ${imsi}"; return 1
  fi
}

webui_abone_sil() {
  # $1=imsi
  _mongo_eval "db.subscribers.deleteOne({imsi:\"$1\"}); print('deleted');" >/dev/null \
    && c_ok "EPC abonesi silindi: $1"
}

webui_abone_listele() {
  _mongo_eval 'db.subscribers.find({}, {imsi:1, msisdn:1, _id:0}).forEach(function(d){ print(d.imsi + "  " + (d.msisdn?d.msisdn.join(","):"")); });'
}

webui_abone_var_mi() {
  # $1=imsi -> 0 varsa
  local n; n=$(_mongo_eval "db.subscribers.countDocuments({imsi:\"$1\"})" 2>/dev/null | tr -dc '0-9')
  [ "${n:-0}" -ge 1 ]
}
