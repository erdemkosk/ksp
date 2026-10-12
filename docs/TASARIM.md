# Oyun Tasarım ve Teknik Analiz

KSP + BDArmory tarzı: gezegen üzerinde parçalardan savaş uçağı tasarla, uç, savaş, görev yap.
Motor: **Godot 4.7 (GDScript)**, 3D.

---

## 1. Oyun Döngüsü (Core Loop)

```
Hangar (parçalardan uçak yap)
   → Pist / havada başlat
      → Uç, radarla hedef bul, silahla vur
         → Görev sonucu (para / itibar)
            → Yeni parça aç → tekrar Hangar
```

Oyunun kalbi iki şey: **uçuş hissi** ve **tasarımın sonucu etkilemesi** (kötü kanat yerleşimi = uçak uçmaz).
Bu yüzden ilk iş grafik değil, aerodinamik + parça birleştirme sistemi.

---

## 2. MVP Kapsamı (az parça)

| Kategori | Parça | Önemli özellikleri |
|---|---|---|
| Kokpit | Tek kişilik kokpit | kütle, HP, kontrol noktası, küçük yakıt |
| Gövde | Yakıt tankı (kısa / uzun) | kütle (yakıta göre değişir), yakıt |
| Motor | Jet motoru | itki, yakıt tüketimi, ısı imzası (IR füze için) |
| Kanat | Ana kanat | kaldırma alanı, sürükleme |
| Kontrol | Kontrol yüzeyi (elevon) | pitch/roll/yaw eksen ataması, sapma açısı |
| Kontrol | Dikey kuyruk | yaw stabilitesi |
| Burun | Burun konisi | düşük sürükleme |
| İniş | İniş takımı | tekerlek, fren |
| Silah | Top (gun) | atış hızı, mermi hızı, hasar, cephane |
| Silah | Pilon + IR füze | arayıcı konisi, menzil, itki süresi |
| Sensör | Radar | tarama konisi, menzil, kilit |

~11–12 parça. Yeni parça eklemek sadece yeni bir veri dosyası + model olacak şekilde tasarlanmalı (bkz. §4).

---

## 3. Mimari Kararlar (en kritik kısım)

### 3.1 Araç fiziği: Tek RigidBody, parça başına joint YOK
KSP her parçayı joint ile bağlar → "wobble", patlama, performans sorunu. Önerimiz:

- Uçak = **tek `RigidBody3D`**. Parçalar onun altında `Node3D` + kendi `CollisionShape3D`'leri.
- Kütle, ağırlık merkezi (CoM) ve atalet parça verilerinden **hesaplanır** (`center_of_mass_mode = CUSTOM`).
- Bir parça yok edilince → o parça ve ona bağlı alt ağaç **ayrı bir RigidBody olarak kopar** (kanat kopması vb.), ana gövde kütlesi yeniden hesaplanır.
- Bu hem stabil hem ucuz, hem de BDArmory'deki "parça parça dağılma" hissini veriyor.

Fizik motoru: **Jolt** (Project Settings → Physics → 3D). Fizik tick: 60 Hz, gerekirse 120.

### 3.2 Aerodinamik: parça bazlı kuvvet
Her `WingModule` her fizik karesinde:
1. Kendi konumundaki hava hızını hesaplar: `v = linear_velocity + angular_velocity × r`
2. Hücum açısı (α) bulur
3. `Cl(α)` (≈ 2π·α, ~15°'de stall ile düşüş), `Cd = Cd0 + k·Cl²`
4. `L = ½ ρ v² S Cl`, `D = ½ ρ v² S Cd`
5. `apply_force(kuvvet, parça_konumu)`

Hava yoğunluğu `ρ(irtifa)` üstel azalır → yüksekte motor/kanat zayıflar. Bu basit model bile CoM/CoL dengesinin önemli olmasını sağlar; gerçekçi uçuşun %80'i buradan gelir.

### 3.3 Gezegen ve koordinat hassasiyeti
- Godot standart derlemesi `float` (32-bit) → orijinden ~10 km sonra titreme.
- **Floating origin baştan yapılmalı**: oyuncu belirli mesafeyi geçince tüm dünya geri kaydırılır.
- MVP: büyük düz/yükseklik haritalı arazi + sabit aşağı yerçekimi.
- Sonra: küresel gezegen (yerçekimi yönü merkeze doğru, chunked LOD arazi). Kodu baştan `Gravity.get_at(pos)` gibi bir arayüzle yazarsak geçiş ağrısız olur.

### 3.4 Parça sistemi: veri + modül (kompozisyon)
KSP'deki `PartModule` mantığı:

```
PartData (Resource .tres)
  id, isim, kategori, kütle, maliyet, max_hp
  scene: PackedScene (model + collider)
  attach_nodes: [{konum, yön, boyut}]
  modules: [EngineModuleData, WingModuleData, ...]
```

Modüller (runtime `Node`):
`EngineModule`, `FuelTankModule`, `WingModule`, `ControlSurfaceModule`,
`WeaponModule` (Gun / MissileLauncher), `RadarModule`, `CockpitModule`, `LandingGearModule`.

Uçak çalışırken modüller **olay/arayüz** üzerinden konuşur (`Vessel.get_modules(RadarModule)` gibi). Böylece "radarı olmayan uçak radar füzesi atamaz" kuralı kendiliğinden çıkar.

### 3.5 Uçak kayıt formatı (craft)
JSON — insan okunur, mod dostu:
```json
{
  "name": "Kartal-1",
  "parts": [
    {"uid": 0, "part": "cockpit_mk1", "parent": -1, "pos": [0,0,0], "rot": [0,0,0,1]},
    {"uid": 1, "part": "tank_short",  "parent": 0, "node": "rear", "pos": [0,0,-2], "rot": [0,0,0,1]},
    {"uid": 2, "part": "wing_main",   "parent": 1, "surface": true, "pos": [1.2,0,-2], "rot": [...], "sym": 3}
  ]
}
```

### 3.6 Hangar (SPH editörü)
Olmazsa olmazlar:
- Attach node'a yapışma + yüzeye yapıştırma (kanatlar için)
- **Simetri** (ayna, x2)
- **CoM / CoL / itki göstergeleri** — oyuncunun uçağın uçup uçmayacağını görmesi için şart
- Geri al (undo), kaydet/yükle, maliyet & kütle özeti
- Kontrol yüzeyi eksen ataması (pitch/roll/yaw tikleri)

---

## 4. Savaş Sistemleri (BDArmory tarafı)

### Silahlar
- **Top**: mermiler RigidBody DEĞİL. Bir `ProjectileManager` dizide tutar, her kare yerçekimi + hız ile ilerletir, `PhysicsRayQuery` ile çarpışma kontrol eder. Yüzlerce mermi rahat.
- **Füze**: ayrı küçük RigidBody, **Proportional Navigation** güdümü, sınırlı itki süresi ve dönüş G limiti.
  - IR: motor ısı imzasına kilitlenir, arayıcı konisi, flare ile kandırılabilir.
  - (Sonra) Radar füzesi: radar kilidi gerekir, chaff.

### Hasar
- Her parçanın HP'si. Mermi isabeti → o parça. Patlama → yarıçap içindeki parçalara mesafeyle azalan hasar.
- HP 0 → parça kopar/yok olur (§3.1). Kokpit giderse uçak kontrolsüz; motor giderse itki yok.

### Radar
- Tarama konisi + menzil. Tespit: `algılama = f(hedef_RCS, mesafe)` — büyük uçak daha uzaktan görünür (tasarım kararını etkiler!).
- Modlar: Tarama (TWS) → Kilit (STT).
- Hedefin **RWR**'ı (radar uyarı alıcısı) kilitlendiğini görür → kaçınma davranışı.
- HUD'da radar ekranı (B-scope, basit 2D).

### Karşı tedbirler
Flare (IR), Chaff (radar). Sınırlı sayıda.

---

## 5. Yapay Zeka Pilot

İki katman:
1. **Uçuş kontrolcüsü**: hedef yön/hız → PID ile pitch/roll/yaw/throttle. (Aynı kontrolcü oyuncu için "SAS" olarak da kullanılır.)
2. **Taktik durum makinesi**: `Devriye → Tespit → Yaklaş → Saldır → Kaç (füze uyarısı) → Uzaklaş (extend) → tekrar`

Silah yöneticisi: menzile ve açıya göre top mu füze mi seçer. AI oyuncunun yaptığı uçaklarla da uçabilmeli (BDArmory'deki gibi AI-vs-AI turnuva ileride harika bir özellik).

---

## 6. Görev Sistemi

Veri odaklı (`MissionData` Resource veya JSON):
```
başlık, açıklama, harita, başlangıç (pist/havada)
spawnlar: [{craft: "dusman_avci.json", konum, ai_profil}]
hedefler: [DestroyAll(grup), ReachWaypoint, Survive(süre), Intercept(bombacı), Escort]
ödül: para, açılan parçalar
kısıt: max_maliyet, yasak_parçalar
```
MVP görevleri: 1) Pistten kalk ve waypoint'e uç, 2) Yer hedeflerini vur, 3) 1v1 it dalaşı, 4) 2 düşmanı radarla bul ve vur.

İlerleme: para → parça açma (basit teknoloji ağacı, sonra).

---

## 7. Klasör Yapısı (öneri)

```
ksp/
  project.godot
  core/            # Game, floating origin, gravity, atmosfer, save/load
  vessel/          # Vessel (RigidBody), VesselBuilder (JSON→sahne), modüller
    modules/
  parts/           # her parça bir klasör: data.tres + model + scene
    cockpit_mk1/
    tank_short/
    ...
  combat/          # ProjectileManager, Missile, Damage, Radar, Countermeasures
  ai/              # FlightController (PID), AIPilot (state machine)
  editor_hangar/   # SPH editörü
  missions/        # MissionData, hedef tipleri, görev dosyaları
  ui/              # HUD, radar ekranı, menüler
  world/           # arazi, pist, gezegen
  crafts/          # kayıtlı uçaklar (.json)
  docs/
```

---

## 8. Yol Haritası

| Faz | Hedef | Bitti sayılır eğer… |
|---|---|---|
| **0 – Uçuş prototipi** | Elle kurulmuş bir uçak düz arazide uçar | Kalkış, dönüş, stall, iniş hissediliyor |
| **1 – Parça sistemi** | PartData + modüller + JSON → uçak oluşturma | Aynı uçak JSON'dan oluşup aynı uçuyor |
| **2 – Hangar** | Parça yerleştir, simetri, CoM/CoL, kaydet | Oyuncu sıfırdan uçabilen uçak yapıyor |
| **3 – Silah & hasar** | Top, IR füze, parça HP, kopma | Sabit hedef vurulup parçalanıyor |
| **4 – Radar & AI** | Radar, RWR, AI pilot, flare | 1v1 AI ile it dalaşı oynanabilir |
| **5 – Görevler** | Görev verisi, hedefler, ödül, parça açma | 4 MVP görevi baştan sona oynanıyor |
| **6 – Büyütme** | Küresel gezegen, yeni parçalar, radar füzesi, yer araçları, mod desteği (.pck) | — |

Faz 0 en önemlisi: uçuş eğlenceli değilse gerisi önemsiz.

---

## 9. Riskler

| Risk | Önlem |
|---|---|
| Joint tabanlı fizik titremesi | Tek RigidBody + kopmada ayrıştırma (§3.1) |
| Float hassasiyeti / büyük harita | Floating origin baştan |
| Aerodinamik ayarı zor | Basit model + debug çizimleri (kuvvet okları) + ayar değerleri Resource'ta |
| Çok mermi = yavaş | Mermiler ray tabanlı, havuzlu |
| AI çok zor / çok aptal | Önce PID kontrolcü sağlam, taktik sonra |
| Kapsam şişmesi | Faz bitmeden yenisine geçme; parça sayısını MVP'de sabit tut |
