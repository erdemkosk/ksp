# Hangar 2.0 — uygulama planı

Amaç: hangarı "KSP gibi parça yapıştırma ekranı" olmaktan çıkarıp **bir hava üssünün atölyesi ve
mühendislik bürosu** yapmak. Dört özellik, önerilen sırayla. Her biri ayrı dosyada; `hangar/hangar.gd`
(~3000 satır, başka oturumlarla paylaşılıyor) yalnızca küçük kancalar alır.

## 0. Önce: test edilmemiş değişiklikler

Aşağıdakiler kabuk erişimi olmayan bir oturumda yazıldı, **oyunda hiç çalıştırılmadı**. Önce proje
derleniyor mu (`--hangar --hangartest`, `--hangartreetest`, `--air --feeltest`, `--partsprobe`),
sonra her biri gözle kontrol edilmeli:

| Değişiklik | Dosya | Kontrol |
|---|---|---|
| Füze modeli (raydaki = uçan), X kanatçıklar, alev shader'ı, ışık | `combat/missile.gd`, `parts/part_library.gd` `_missile_visuals` | kanatçıklar gövdeye oturuyor mu, alev lülenin arkasında mı |
| Füze kamerası fare bakışı, tekerlek, orta tık | `camera/flight_camera.gd` `_mc_place`, `controls/player_controller.gd` | sağa-sola dönüş yönü doğru mu |
| Chaff şerit bulutu + pus | `combat/chaff.gd` | `inherit` yok, `look_at` yönü, `Effects._ramp` 3 renk |
| Kumandalı (ram-air) paraşüt, pilot duruşu, fren ipleri | `pilot/pilot_character.gd` | A/D dönüş yönü, kanat şekli, bacaklar |
| Paraşütte fare serbest | `controls/player_controller.gd` | zaman hızlandırma tıklanıyor mu |
| Büyütülmüş kokpitte kanopi oranı | `vessel/modules/cockpit_module.gd` `_build_canopy` | sivil kokpit ×1.5 |
| AWACS burun kokpiti | `crafts/awacs.json` | denge |
| Pervaneli motor kapakları | `parts/part_library.gd` `_cowl_caps` | turboprop / P-26 önden |
| Ağır uçak geç tepki | `vessel/modules/control_surface_module.gd` `response_factor`, `player_controller.gd` | Turna / AWACS |
| Ağır kargo bölmesi, kargo rampası, Herkül C-130 | `parts/part_library.gd`, `crafts/herkul.json` | hangar uyarıları, kalkış |
| Ağır Nakliye görevi | `missions/mission_manager.gd` `_check_freight`, `world/ambient_air.gd` | görev açılıyor, boşaltma sayacı |
| Rüzgâr tüneli (§1, uçuş koduna dokunmadan: kanat hesabının statik kopyası) | `hangar/wind_tunnel.gd`, hangar üst çubuk düğmesi + `_toggle_tunnel` | panel açılıyor mu, duman çizgileri, renkler, grafik |
| Görsel tasarım panosu: karakter altıgeni (önceki tasarıma göre ▲/▼), denge terazisi (ağırlık / kaldırma merkezi, boş yakıtta kayma), T/W · kanat yükü · hava alığı göstergeleri, kalkış pisti; rakamlar "Ayrıntılar ▸" altında katlı; sağ panel kaydırmalı | `hangar/design_dashboard.gd`, hangar `_build_ui` sağ panel + `_update_stats` | panel 300 px'e sığıyor mu, boş uçakta çökmüyor mu, tooltip |
| Sorunlu parçaların üstünde zıplayan 3B ⚠ işaretleri | hangar `_warn_markers`, `_parts_of` (eski `_blink` döngüsü) | işaret boyu, uçak yeniden kurulunca eski işaretler siliniyor mu |
| Canlı hangar (§4'ün bir kısmı): teknisyenler, alet arabası, merdiven, F12 fotoğraf | `hangar/hangar_life.gd`, hangar `_ready` kancası | teknisyenler uçağın içinden geçmiyor mu, fotoğraf kaydı |

**Durum (13 Eki):** §1 ve §4'ün bir kısmı yazıldı (yukarıdaki satırlar, test edilmedi). §2 **filo** diğer
oturumun `core/designs.gd` + `hangar/production_dialog.gd` (prototip güvenilirliği, hizmet kaydı, seri
üretim) işiyle örtüşüyor: kuyruk numaralı uçaklar ve parça hasarı onun üstüne kurulmalı, o oturumla
anlaşarak. §3 **silahlandırma** uçuşa çıkış akışına (`ui/briefing.gd`, `main.gd`) dokunuyor — yine o
oturumun alanı. Burun resmi / arma yuvaları ve saate göre hangar ışığı yapılmadı.

Hepsi geçince commit + push (kullanıcı: master'a).

---

## 1. Rüzgâr tüneli (görerek tasarım)

**Dosya:** `hangar/wind_tunnel.gd` (Node3D + kendi Control paneli). Hangar üst çubuğuna bir düğme:
"Rüzgâr tüneli". Açıkken yerleştirme kapalı, kamera serbest.

**Fizik verisi:** `WingModule.physics_tick` bugün kuvveti hesaplayıp doğrudan uygular. Bölünmeli:
- `func evaluate(air_vel: Vector3, density: float) -> Dictionary` → `{lift, drag, cl, aoa, stalled, buffet, pos}`
  (shock, vortex, tip stall, sideslip, ground effect dahil — bugünkü hesabın aynısı)
- `physics_tick` = `evaluate(vessel.air_velocity_at(...))` + `add_force_at`.
Tünel, `evaluate`'i uçak uçmadan, istenen hız / hücum açısı / yandan kayma ile çağırır.
`BodyDragModule` için de aynı ayrım.

**Görseller:**
- **Duman çizgileri:** uçağın önünde dikey bir ızgaradan çıkan `TrailRibbon` / `GPUParticles3D`
  çizgileri; her adımda en yakın kanadın `cl`'sine göre aşağı/yukarı saptırılır (kozmetik). Stall
  olan yüzeyin arkasında çizgiler dağılır, kırmızıya döner.
- **Yüzey rengi:** her parçaya `material_overlay` (hangar `_set_overlay` zaten var):
  kanatlarda `cl / cl_max` (mavi → yeşil → kırmızı), stall'da yanıp sönen kırmızı.
- **Yük haritası:** seçilen G'de (kaydırıcı, 1–9 G) her parçanın yükü / `part.strength`
  (`Vessel._structural_loads` mantığı statik çalıştırılır) → yeşil → kırmızı; %100 üstü "kırılır".
- **Grafik:** panelde CL–hücum açısı eğrisi (-5°…30°), L/D, stall noktası, kaldırma merkezi
  kayması; Mach kaydırıcısıyla transonik şok ve Mach tuck görünür. Control `_draw` ile.

**Kaydırıcılar:** hız (km/sa), hücum açısı, yandan kayma, irtifa, G. "Kontrol yüzeyi sapması"
kaydırıcısıyla elevon etkisi (yunuslama momenti) gösterilir.

---

## 2. Filo: hangar bir üs

**Veri (`core/career.gd` + `user://career.json`):**
```
fleet: [{
  "id": "TC-01", "design": "<tasarım adı>", "craft": {<tasarımın o anki kopyası>},
  "wear": 0.12, "damage": {"<part uid>": 0.6, ...}, "hours": 3.4, "sorties": 7,
  "pilot": <Crew indeksi|-1>, "status": "hazır" | "bakımda" | "kayıp", "ready_day": 5
}]
```
- **Üret:** hangarda "Filoya ekle" → tasarımın kopyası, bedel `Career.craft_cost(craft)`.
- **Uçuşa çıkış:** görev seçiminden önce filodan uçak seç → `Game.flight_craft = craft`,
  `Game.fleet_id = id`. Uçak kayıtları (craft parts) `uid` taşır (CraftTree).
- **Uçuş sonu (`main.end_flight`):** `vessel.parts[i].get_meta("bi")` → kayıt indeksi → `uid` ile
  her parçanın `health_ratio()` filo kaydının `damage`ına; `wear` (zaten artıyor), `hours`,
  `sorties`; uçak düştüyse / fırlatıldıysa `status = "kayıp"`.
- **Hasar hangarda görünür:** `VesselBuilder.build(craft)` kayıttaki `damage`'ı okur → parça
  `hp`'si düşük kurulur, `DamageFx` is/yanık kaplaması ve kurşun deliği decal'ları uygulanır.
- **Onarım:** hasar oranına göre para + gün (`Career.day`); "bakımda" uçak uçamaz. "Boyayı yenile"
  `wear`'ı sıfırlar (para).
- **Hazırlık:** cephe haritasında (`menu/theater_map.gd`) "Filo: 4 hazır · 2 bakımda · 1 kayıp".
  Kötü giden savaşta yorgun / hasarlı uçakla çıkma kararı oyuncunun.
- **Hasarlı uçakla uçuş:** parçalar düşük `hp` ile başlar (yapı daha erken kırılır, kanat daha
  az kaldırır — `WingModule` zaten `health_ratio` kullanıyor).

**Yeni dosyalar:** `core/fleet.gd` (veri + kurallar), `hangar/fleet_panel.gd` (liste, üret,
onar, seç). Hangar kancası: üst çubukta "Filo" düğmesi.

---

## 3. Silahlandırma ekranı (tasarım ≠ görev donanımı)

**Fikir:** gövde (airframe) bir kez tasarlanır; her görevden önce ayrı bir ekranda askılara yük,
yakıt, flare / chaff seçilir. Hangarda her görev için parça sökmek gerekmez.

**Veri:** filo kaydında `loadout`:
```
loadout: {"stores": {"<askı uid>": "<parça id>", ...}, "fuel": 0.8, "flares": 30, "chaff": 20}
```
- Askılar: `pylon` parçaları, `mount: "tip"` raylar, gövde altı noktalar. Uygun yük listesi
  `_pylon_load(def)` kuralından (hangar'da var).
- Kurulumda `VesselBuilder.build` tasarımın silah / harici yük kayıtlarını atlar, `loadout`'taki
  yükleri askıların altına yerleştirir (hangar'daki askı-altı konum hesabı: `_refresh_nodes`
  pylon dalı). Yakıt: tank kayıtlarına `fuel` tweak'i (zaten var).
- **Ekran:** `ui/loadout_panel.gd`; görev brifinginin (`ui/briefing.gd`) "Başla"sından önce açılır.
  Uçağın üstten şeması, her askıya tıkla → açılır liste; kütle, menzil, itki/ağırlık canlı.
  Brifingdeki istihbarat önerisi (`Front.INTEL[id].advice`) yanında görünür.
- Kariyer: mühimmat stoğu (para ile alınır) — atılan füze / bomba stoktan düşer.

---

## 4. Canlı hangar (atmosfer)

- **Teknisyenler:** `PilotModel` + `pose_walk` (pilot karakterinde var) ile uçağın çevresinde
  yürüyen 2–3 kişi; durup uçağa bakar, merdiven taşır. Hasarlı uçakta panelleri açık, yerde alet
  kutusu; bakımdaki uçağın motoru sehpada sökülü durur.
- **Işık:** `Weather` saatine göre hangar kapısından gün ışığı / gece floresan ve kırmızı ikaz
  lambaları; yağmurda kapıda su damlaları.
- **Boya ve burun resmi:** boya paneline (hangar `_build_paint_ui`) decal yuvaları: burun resmi,
  filo arması, kuyruk kodu — `Decal` düğümleri ya da `Label3D` + doku; konum ve ölçek sürüklenir.
  `paint` craft kaydında saklanır.
- **Fotoğraf köşesi:** "Fotoğraf çek" → arayüz gizlenir, serbest kamera, odak / pozlama, PNG
  `user://photos/`. Uçuşta da (F12) aynı mod.

---

## Önerilen sıra ve büyüklük

1. **Rüzgâr tüneli** — orta; önce `WingModule.evaluate` ayrımı (uçuşu bozmadığı `--feeltest` ile
   doğrulanmalı), sonra görseller.
2. **Filo** — büyük; kariyer kaydı biçimi değişir (eski kayıtlar için geçiş: filo boşsa mevcut
   tasarımdan bir uçak oluştur).
3. **Silahlandırma** — orta; filoya bağlı (`loadout` filo kaydında).
4. **Atmosfer** — küçük parçalar halinde, her biri bağımsız.

Her adımda: projenin derlendiğini kontrol et, ekran görüntüsü al, ilgili testi çalıştır.
Kariyer kaydına yazan testler argüman adı `test` / `probe` / `demo` ile bitmeli (`Crew._testing`).
