# Docker Open5GS VoLTE & SMS over IMS

Bu repository, [herlesupreeth/docker_open5gs](https://github.com/herlesupreeth/docker_open5gs) üzerine inşa edilmiş olup, **VoLTE (Voice over LTE) ve SMS over IMS** testleri için donanımla kanıtlanmış, çalışan bir yapılandırma içerir. Orijinal yapıya SMSC entegrasyonu, iFC (Initial Filter Criteria) REGISTER yönlendirmeleri ve gerçek donanım testleriyle doğrulanmış VoLTE ayarları eklenmiştir.

## 1. Sistem Ne Yapar?
Bu yapılandırma, bir USRP B210 ve programlanabilir SIM kartlarla kapalı devre bir 4G/LTE ağı kurmanızı sağlar.
- **VoLTE Çağrısı:** İki ticari telefon arasında IP üzerinden (IMS) yüksek kaliteli sesli arama.
- **SMS over IMS:** Cihazlar arası SIP MESSAGE metoduyla çalışan, kanıtlanmış SMS gönderimi/alımı.

## 2. Donanım ve Sistem Ön Koşulları
- **Radyo (SDR):** USRP B210 (veya muadili uyumlu bir SDR)
- **SIM Kart:** Programlanabilir sysmoISIM veya muadili (Milenage destekli, SQN check kapatılabilen)
- **SIM Kart Okuyucu:** PCSC destekli herhangi bir smart card reader
- **İşletim Sistemi:** Ubuntu 22.04 LTS
- **Yazılımlar:** Docker, Docker Compose, UHD (USRP Hardware Driver), pySim (SIM programlama için)

## 3. Adım Adım Kurulum

### Hızlı Başlangıç (Tek Komutla Kurulum)
Sıfırdan tam çalışan bir VoLTE sistemi kurmak için `install.sh` scriptini kullanabilirsiniz. Bu script donanım gereksinimlerini, docker container'larını ve ayarları otomatik yapılandırır.
```bash
git clone <bu-repo-url>
cd <bu-repo>
./install.sh
./scripts/abone_ekle.sh --imsi <IMSI> --ki <KI> --opc <OPC> --msisdn <MSISDN>
./scripts/volte start
```

---

### Bağımlılıkların Kurulması (Manuel)
Sisteminizde Docker ve UHD sürücülerinin kurulu olduğundan emin olun:
```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 uhd-host uhd-soapysdr
```

### Konfigürasyonun Hazırlanması
Repoyu indirdikten sonra çevre değişkenlerini ayarlayın:
```bash
cp .env.example .env
nano .env
```
`.env` dosyası içinde `DOCKER_HOST_IP` değerini makinenizin LAN IP adresiyle değiştirin. Ayrıca SIM kartınıza yazacağınız `IMSI`, `KI` ve `OPC` değerlerini de burada belirleyin.

### SIM Kartın Programlanması
IMS ve VoLTE'nin sorunsuz çalışabilmesi için SIM kartın doğru programlanması kritik öneme sahiptir:
- **SQN (Sequence Number) Check:** Kapatılmalıdır (Aksi takdirde HSS ile senkronizasyon kayıpları yaşanır).
- **Tip:** `OPc` kullanılmalıdır.
- pySim aracı ile SIM kartınızı `.env` dosyanızdaki değerlerle eşleşecek şekilde programlayın.

### Ağ Geçidi (xfrm) Modüllerinin Yüklenmesi
IPsec tünellerinin çalışması için çekirdek modüllerini yükleyin:
```bash
sudo modprobe xfrm_user
sudo modprobe xfrm_algo
```

### Çekirdek ve IMS'in Başlatılması
```bash
sudo docker compose -f 4g-volte-deploy.yaml up -d
```
Bu komut, Open5GS çekirdek ağ bileşenlerini, Kamailio IMS sistemini, HSS ve SMSC'yi başlatır.

### Abone Ekleme (Detaylı Bilgi ve HSS + pyHSS Mantığı)
Sistemin mimarisinde **İKİ AYRI HSS** bulunmaktadır ve VoLTE+SMS çalışması için abonenin **her ikisine de** kaydedilmesi zorunludur:

1. **WebUI (Open5GS HSS) - EPC ve Attach için:** `http://<DOCKER_HOST_IP>:9999` üzerinden eklenir. Telefonun 4G ağına (EPC) attach olması ve internete çıkması için şarttır. Burada IMSI, Ki, OPc, APN (internet + ims) ve MSISDN tanımlanır.
2. **pyHSS (IMS HSS) - VoLTE ve SMS için:** `http://<DOCKER_HOST_IP>:8080/docs` REST API'si üzerinden 5 ayrı adımda (APN, AUC, Subscriber, IMS_Subscriber) provisioning yapılır. Bu adım eksik olursa S-CSCF kaydı gerçekleşmez ve VoLTE çalışmaz. Özellikle `ims_subscriber` adımında `default_ifc.xml` belirtilmesi I-CSCF ve S-CSCF yönlendirmesi için kritiktir.

> **KOLAY YOL (ÖNERİLEN):** Manuel olarak her iki veritabanına ekleme yapmak yerine hazırladığımız `abone_ekle.sh` scriptini kullanarak tek komutla bu işlemi hatasız gerçekleştirebilirsiniz:
> ```bash
> ./scripts/abone_ekle.sh --imsi <IMSI> --ki <KI> --opc <OPC> --msisdn <MSISDN>
> ```

---

## 3.1 Script Kullanımı ve Yönetim Araçları
Bu repo, sistemin yönetimini kolaylaştırmak için aşağıdaki scriptleri içerir:

- `./install.sh` : Sıfırdan donanım/yazılım bağımlılıkları dahil tam kurulum sağlar.
- `./tara_kur.sh` : Önceden var olan ancak VoLTE yapılandırması eksik olan mevcut Open5GS klasörünü tarar ve gerekli VoLTE+SMS yapılandırmalarını yedekleyerek ekler.
- `./scripts/volte` : Sistem durumunu kontrol etmek ve başlatıp durdurmak için kullanılan CLI'dır.
  - `./scripts/volte start` : EPC ve eNB radyosunu başlatır.
  - `./scripts/volte stop` : eNB radyosunu durdurur.
  - `./scripts/volte stop --all` : Tüm sistemi (çekirdek dahil) durdurur.
  - `./scripts/volte status` : Container durumlarını gösterir.
  - `./scripts/volte corestatus` : Sadece çekirdek+IMS bileşenlerinin (mme, amf, pcscf, scscf, pyhss, smsc vb.) detaylı sağlık durumunu gösterir.
- `./scripts/abone_ekle.sh` : Yukarıda anlatıldığı gibi EPC ve IMS'e aynı anda abone ekler.
- `./scripts/plmn.sh` : Sistemin mevcut PLMN (MCC/MNC) bilgilerini değiştirmek için kullanılır. (--mcc ve --mnc parametreleri alır).

### eNB'nin Başlatılması
Radyoyu ayağa kaldırmak için srsENB'yi çalıştırın:
```bash
sudo docker compose -f 4g-volte-deploy.yaml up srsenb
```

## 4. Telefonda VoLTE ve SMS Açma
Ticari telefonlarda (özellikle Xiaomi, Redmi gibi) VoLTE carrier check mekanizmasını kapatmak gerekebilir:
- Arama ekranına `*#*#86583#*#*` yazın ("VoLTE carrier check was disabled" uyarısını görün).
- Cihaz ayarlarından yeni bir APN oluşturun (İsim: `ims`, APN: `ims`, APN Tipi: `ims`, Protokol: IPv4).

## 5. Doğrulama ve Test
Telefonu ağa bağladığınızda sırasıyla şunlar olmalıdır:
1. **Attach:** `mme` loglarında `Attach Complete` mesajını görün.
2. **REGISTER:** `scscf` loglarında `REGISTER` ve ardından `200 OK` mesajlarını görün (IMS kaydı başarılı).
3. **SMS:** Bir telefondan diğerine SMS gönderin. `smsc` loglarında `MESSAGE sip:...` ve `MT SMS delivered` mesajlarını göreceksiniz.
4. **Çağrı:** Aramayı başlatın. `pcscf` ve `scscf` üzerinden `INVITE` paketlerinin aktığını izleyin.

## 6. Önemli Dosyalar ve Scriptler
- `4g-volte-deploy.yaml`: Tüm 4G ve VoLTE container'larını ayağa kaldıran ana docker-compose dosyası.
- `pyhss/default_ifc.xml`: SMS ve Ses çağrıları için Kamailio'ya yönlendirme kurallarını (Initial Filter Criteria) içerir. *Bu repoda REGISTER yönlendirmesi SMS için özel olarak aktifleştirilmiştir.*
- `scscf/scscf.cfg`: S-CSCF ayarları. (Burada `rtimer` değerleri SMS beklemelerine uygun şekilde optimize edilmiştir).
- `srsenb/enb.conf`: SDR radyo yayın konfigürasyonu. EARFCN ve bant ayarları bu dosyadan yapılır.

## 7. Sorun Giderme
- **SMS Gitmiyor:** Telefonun IMS-SMS destekleyip desteklemediğini kontrol edin. `scscf` loglarında REGISTER işleminin yapıldığından emin olun.
- **VoLTE Simgesi Çıkmıyor:** Telefonun gizli menülerinden VoLTE'yi zorladığınızdan ve `ims` APN'sinin doğru yapılandırıldığından emin olun.
- **Radyo Başlamıyor:** USRP'nin USB 3.0 portuna bağlı olduğunu ve `uhd_find_devices` komutuyla göründüğünü doğrulayın.

## Lisans ve Atıf
Bu proje [herlesupreeth/docker_open5gs](https://github.com/herlesupreeth/docker_open5gs) kaynak alınarak oluşturulmuştur. Orijinal lisans koşulları geçerlidir. Bu çatalda (fork), VoLTE yapılandırmaları iyileştirilmiş ve tam çalışan "SMS over IMS" konfigürasyonları (iFC, rtimer, smsc ayarları) entegre edilmiştir.
