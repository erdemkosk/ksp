# Hangar Savaşları (Prototip)

KSP + BDArmory tarzı parça tabanlı savaş uçağı oyunu. Godot 4.7.
Tasarım ve yol haritası: [docs/TASARIM.md](docs/TASARIM.md)

## Çalıştırma
Godot editöründe `project.godot`'u aç → F5. Ya da:
```
Godot_v4.7.2-stable_win64.exe --path .
```

## Kontroller
| Tuş | İş |
|---|---|
| W / S · Q / E · A / D | burun · yatış · sapma |
| Shift / Ctrl · Z / X | gaz + / − · tam gaz / kes (gaz %95+ = afterburner) |
| Alt + W/S · T · U | trim · SAS · otopilot (irtifa + yön tut) |
| G · B · P | iniş takımı · fren · park freni |
| I · L · K | otomatik marş (çalışıyorsa motoru kapatır) · ışıklar · kanopi |
| F | dışarı çık / uçağa bin (yerde: WASD, Shift koş, Ctrl yavaş, Space zıpla, fare bakış, Alt imleç) |
| C | kamera: takip → kokpit → serbest |
| Sağ tık + sürükle · tekerlek · orta tık | etrafa bak · zoom · sıfırla |
| Sol tık (kokpit) | kokpit anahtarlarını kullan |
| Sağ tık (parça, dış kamera) | KSP gibi parça penceresi: sağlık, yük, motor/yakıt/kanat/takım durumu ve düğmeleri |
| Space · V · O | ateş · silah seç (top / füze / bomba) · flare at |
| F4 · sol tık (hedef kutusu / radar) | radar hedefi seç — füze arayıcısı önce ona kilitlenir |
| 1-9 | **eylem paneli** (sol alt): fren paraşütü aç/kes, hava freni, takım, fişek, motor, kanopi, pilot indirsin, uçuşu bitir |
| ⌫ ⌫ (iki kez) | **fırlatma koltuğu** |
| F2 | telsiz: kalkış / iniş izni, en yakın meydana yön, hava durumu, mayday, pilot indirsin |
| M | bölge haritası (tekerlek yakınlaştırır) |
| F9 · F10 | uçuşu kaydet · kayıttan devam (ana menüde "Devam et") |
| F7 | saldırgan düşman avcı çıkar |
| F5 · F6 · , / . | hava durumu · saat atla · zaman hızı |
| R / H | piste dön / havada başla |
| F1 · F3 | tuşlar penceresi · aerodinamik debug |
| J | hangara dön |

## Kariyer: para, Ar-Ge, görev ödülleri
- Görev ödülü zorluğa göre (★ 6.000 · ★★ 11.000 · ★★★ 18.000 ₺), tekrarında yarısı; başarısız görevde
  küçük katılım payı. ★★ görevler 2, ★★★ görevler 5 tamamlanmış görevle açılır.
- Hangarda kilitli (🔒) parçalar **Ar-Ge** ile açılır (parça fiyatının 4 katı). Kilitli parçalı uçak piste çıkamaz.
- Uçak kaybı (düşme / fırlatma) parça bedelinin yarısı kadar sigorta payı keser; meydanda güvenli iniş bedavadır.
- Yeni pilot almak 4.000 ₺. Ayarlar → **Serbest mod**: her şey açık, para yok.
- Hangarda **performans tahmini**: kalkış hızı ve mesafesi, deniz seviyesi ve 8 km azami hız, tırmanma,
  dayanım, menzil, yakıt bitince ağırlık merkezinin kayması.

## Düşmanlar ve yeni görevler
- **SAM rampası**: 9 km, yerden 120 m üstü ve görüş hattında radar kilitlenir, 3.5 sn sonra füze atar. Alçak
  uçuş (arazi maskeleme), flare ve sert dönüş kurtarır. Haritada menzil çemberi görünür.
- **Uçaksavar topu**: 3 km, öncül nişanlı izli seriler. **Konvoy**: yolda ilerleyen kamyon ve zırhlılar.
- **Saldırı helikopteri**: alçakta devriye, yaklaşan uçağa dönüp ateş eder; vurulunca dönerek düşer.
- Düşman **Şahin-B** (ağır avcı / bombardıman) ve Kartal karışık gelir.
- Yeni görevler: **Helikopter Avı** (★★), **Hava Savunmasını Kır** (★★★); Kara Saldırısı artık hareketli konvoy.
- Paraşütle inen pilota **kurtarma helikopteri** gelir, yanına iner; yürüyüp binince (F) üsse götürür.

## Kısmi arızalar
Kanat isabet aldıkça kaldırması düşer (tek taraf hasarlıysa uçak o yana yatar), kumanda yüzeyi ağır hasarda
o anki açısında **sıkışabilir**, gövde isabeti **hidrolik sızıntısı** açabilir (kumanda yavaşlar ve zayıflar),
motorlar durunca yalnız yedek RAT basıncı kalır, ağır hasarlı motor **tekler**. Sarı ikaz panelinde listelenir.

## Havaalanı, gece ve aletli iniş
Pist kenar / eşik / son ışıkları, 900 m yaklaşma hattı ve koşan çakar, **PAPI** (2 beyaz + 2 kırmızı = doğru
3° süzülüş), **ILS** iğneleri (PFD'de ve kokpit HUD'unda), rüzgar tulumu, dönen havaalanı feneri, inişte
lastik izleri. Dünyada yollarda araçlar, denizde gemiler, kuş sürüleri, apronda park etmiş uçaklar ve
serbest uçuşta sivil trafik (radarda gri).

## Aerodinamik etkileşim
- **Aşağı akış**: kanat arkasındaki yüzeylerin hücum açısı ε = 2·CL/(π·AR) kadar azalır (yanal örtüşme ve
  yükseklik farkıyla zayıflar) — kuyruk ana kanadın izinde daha az etkili, tandem kanat bedava değil.
- **Gövde yüzleri**: önünde gövde olan parça rüzgardan korunur; açıkta kalan küt burun düz levha gibi direnir,
  kuyruk konisi olmayan küt arka uç taban direnci üretir (burun/kuyruk konisi takmak işe yarar).
- Kanat ve dikey kuyruk köklerinde gövdeyle yumuşak geçiş kaportası (görsel).

## Arazi ve dünya
- Düz ovalarda **tarla deseni** (ürün renkleri, çitler, ekin sıraları), dağdan denize akan **nehirler**
  (arazi oyulur, kıvrımlı), yol kesişimlerinde **köprüler** (araçlar ve konvoy köprüden geçer).
- Kasabalarda beşik çatılı evler ve kat kat pencereli apartmanlar (gece pencereler yanar).

## Kokpit ve pilot
- Kokpit iç yüzeylerinde panel dikişleri, vidalar ve kokpit ışığıyla aydınlanan etiketler; avcıda konsol
  anahtar sıraları, dikiz aynaları, çizgili fırlatma kolu; sivilde tavan paneli ve güneşlikler.
- Pilot modeli profilli gövde, incelen uzuvlar, botlar; uçağa biniş ve iniş tırmanma animasyonu.

## Hedefleme podu (F8)
- **Hedefleme Podu (FLIR/TV)** parçası (sensör, Ar-Ge; Şahin-B'de takılı): podun döner optik başlığından canlı
  görüntü solda kendi panelinde açılır (savaş paneli o sırada katlanır).
- Modlar: TV, IR beyaz-sıcak, IR siyah-sıcak (motorlar, araçlar, yanan hedefler parlar), gece görüşü.
- Numpad 8/2/4/6 kaydır, +/- yakınlaştır (4 kademe), 5 kilit (araca / yer hedefine ya da noktaya; uçak dönse de
  bakmaya devam eder, kilitli uçak radar hedefi olur), 0 mod, . sıfırla. İmleç serbestken görüntüde sağ tık sürükle,
  tekerlek, sol tık = oraya kilitlen. Ana ekranda podun baktığı nokta "POD" elmasıyla görünür.

## Diğer
- Oyun tam ekran açılır (F11 / Ayarlar). Tuş penceresi başta kapalı (F1).
- İnip durunca ekranın üstünde **UÇUŞU / GÖREVİ BİTİR** düğmesi çıkar (Enter).
- Uçak parçalanırken kokpit sağlamsa kamera kokpitli parçayı izler; fırlatma çalışır (kopan parçalar uçakla
  çarpışmaz, zincirleme dağılma yok). Hava freni kavisli, gövdeyle aynı hizada; yüksek hızda kendini kısar.
- Apronlarda park etmiş uçaklar (Turna yolcu uçakları dahil). Yeni uçak: **Turna** (24 yolcu, çift turbofan).

## Ölçek ve hava freni
- Parçalar gerçek boyutta (dünya ölçeği 1.3: gövde 1.7 m çap). Kütle, alan, itki, yakıt s² ile büyür,
  uçuş performansı aynı kalır; pilot, koltuk, kokpit içi ve cam insan boyunda kalır. Eski kayıtlı uçaklar
  yüklenirken otomatik dönüştürülür.
- **Hava freni** (fren kategorisi, başlangıçtan açık, Kartal-1'de takılı): B basılıyken ön kenarından
  menteşeli panel kalkar; eylem panelinden sürekli açık tutulabilir. Göstergede "HAVA FRENİ" yazar.
- Görev havada bittiğinde sonuç ekranı uçak **yere inip durunca** açılır (hedef işareti en yakın meydanı
  gösterir); pilot kaybedilirse hemen açılır.

## Hangar
Oyun hangarda açılır. Soldan parça seç → parça fareye yapışır, her yerde onu izler (boşlukta kırmızı,
uçağa değince yeşil). Gövde parçası elindeyken boş uçlarda **yeşil bağlantı noktaları** çıkar; fareyi
yaklaştırınca oraya yapışır. Takılı parçaya **sağ tık** → parça penceresi (bilgi, boyut −/+, Taşı,
Kopyala, Sil). **Sol tık** yerleştir
(Shift: seçim kalsın), takılı parçaya **sol tık** tutup taşır, **sağ tık / Del** siler. **Shift+tekerlek** ya da
**[ ]** gövde, motor, kanat ve kontrol yüzeylerini 0.5×–2× boyutlandırır (kütle, itki, yakıt, alan
ölçekle değişir). **Ctrl+Z / Ctrl+Y** geri al / yinele, **Ctrl+S** kaydet, **F** kamerayı ortalar. Gövde parçaları (kokpit, tank, motor,
radom) uç uca eksen boyunca takılır; kanatlar yan yüzeye yatay, üst yüzeye dikey kuyruk olarak;
iniş takımı ve silahlar alta. **X** simetri, **R** döndür. Sağ panel: kütle, itki/ağırlık, kanat
alanı, tahmini stall hızı, maliyet ve kararlılık payı — **sarı** top ağırlık merkezi, **mavi** top
kaldırma merkezi; mavi sarının arkasında olmalı. Kaydet → `user://crafts/`, **PİSTE ÇIK** ile uç.

Sağ üstteki araç çubuğu: **Uçuş** bilgisi, **Otopilot**, **Ortam** (hava/saat/zaman hızı), **Tuşlar**.

## Görevler
Hangarda **PİSTE ÇIK** → görev seç: **Serbest Uçuş**, **Eğitim Uçuşu** (halkalar + iniş), **Keşif**,
**Kara Saldırısı** (konvoy + devriye avcı), **Önleme** (alarm kalkışı, 2 bombardıman, 5 dk),
**İt Dalaşı** (as pilot), **Hava Üstünlüğü** (iki dalga). Sol üstte hedef listesi, ekranda sarı yön
işareti; bitince sonuç ekranı (tekrar / hangar / serbest uçuşa devam). `--mission=it` ile doğrudan.

## Kumanda: fare, klavye, gamepad
- **Fareyle uçuş** (varsayılan): fare dünyada bir nişan belirler (beyaz daire), uçak oraya kendisi döner
  (artı = burun). Klavye/gamepad eksenine dokununca o an elle kumanda. **TAB**: panelleri aç (savaş paneli,
  kumanda paneli, pencere çubuğu; varsayılan ekran temiz) ve imleci serbest bırak
  (paneller, kokpit düğmeleri) / tekrar yakala; **Alt** basılıyken geçici imleç; **Y** fareyle uçuşu kapat.
- **Gamepad** (Xbox düzeni): sol çubuk burun/yatış, sağ çubuk sapma/gaz, RT ateş, LT fren, LB flare,
  Y silah, X takım, B SAS, RB kamera, Start motor, Back park freni.
- **Esc**: duraklatma menüsü (devam, yeniden başlat, ayarlar, hangar, ana menü). Ayarlar: fare hassasiyeti,
  ses, kokpit görüş açısı, kamera sarsıntısı, telsiz.

## His ve görüntü
- Kamera: stall öncesi titreme, türbülans, top atışı, iniş/çarpma darbesi, yakın patlama sarsıntısı;
  kokpitte G ile baş kayması; hız arttıkça görüş açısı hafifçe genişler.
- Hasar: is/yanık kararması, hasarlı parçadan duman, motor/tank yangını (yangın parçayı yakar), delik
  tanktan yakıt sızıntısı (yakıt azalır), hasarlı motor güç kaybeder.
- Hava efektleri: kanat ucu girdap şeritleri, yüksek G'de kanat üstü yoğuşma, 8 km üstünde kontrail, ses
  hızında buhar konisi, iniş temasında lastik dumanı.
- Boya: gri, kamuflaj, deniz, çöl, sivil, kırmızı-beyaz, gece şemaları; ana renk seçimi; panel çizgileri;
  dikey kuyrukta kuyruk numarası, kanat üstünde arma (hangarda BOYA bölümü).
- Kokpit: savaş (tek kişi, HUD camı, iki MFD) ve sivil (yan yana iki koltuk, boynuz lövye, 4 ekran, yandan
  açılan kapı, yardımcı pilot) düzenleri; göz panelden ~0.65 m.
- Sesler: pervane motoru, stall titremesi, kokpitte top gümbürtüsü, yakından geçen mermi vızıltısı, sekme;
  telsiz (kule kalkış/iniş izni, radar uçağı temas bildirimi, "füze atıldı", "hedef düştü").

## Havaalanları, kasabalar, yollar
İki havaalanı (Ana Üs ve ~30 km kuzeybatıda Kuzey Havaalanı), dört kasaba (Ovaköy, Kuzeykent, Yeşilyurt,
Dereköy) ve aralarında yollar. Ekranda yakındaki havaalanı ve kasabaların adı ve uzaklığı görünür.
**Kuzey Seferi** görevi: yolcuları Ana Üs'ten Kuzey Havaalanı'na taşı. Görevlerden önce haritalı brifing.

## Kadro (pilotlar)
Hangarda üst çubuktaki **👤 pilot** düğmesi kadroyu açar: pilot seç, yeni pilot al (en fazla 8).
Her pilotun üç yeteneği var (1–5 yıldız): **Uçuş** (kumanda tepkisi, SAS), **Nişancılık** (top
saçılması), **G dayanımı** (bayılma eşiği). Görev, düşürülen uçak, yumuşak iniş ve yüksek G'de
tecrübe kazanılır; seviye atlayınca en çok kullanılan yetenek artar. Yüksek G'de ekran kenardan
kararır (negatif G'de kırmızı); aşırısında pilot bayılır ve kumandayı bırakır. Kokpit parçalanırsa
pilot **kayıp** olur. Kayıt: `user://crew.json`.

## Sivil görevler ve parçalar
**Yolcu Turu** (konforlu uç, yumuşak in), **Kurtarma** (kazazedelerin yanına arazide in, al, üsse
getir), **Yardım Bırakma** (paraşütlü sandıkları bölgeye at). Parçalar: P-26 pervaneli motor, yolcu
kabini (6 koltuk), kargo bölmesi (4 sandık), düz kanat, hava freni (B), fren paraşütü (yerde B),
yan / burun hava alığı, kanard, ok kanat, dikey kuyruk. Örnek uçaklar: **Kırlangıç** (yolcu),
**Katır** (kargo).

## Fizik notları
- Motorlar **hava alığı** ister (J-70 ≈ 0.5 m²); yetmezse itki düşer, yüksek hücum açısında alık
  verimi azalır. Hangar uyarır. Kokpitin yan girişleri 0.6 m² sayılır.
- Jet itkisi hızla biraz artar (koç basıncı), Mach 2.2 üstünde düşer; pervane itkisi hızla azalır.
- Hangarda kanat, takıldığı yüzeyin açısını alır (açı adımına yapışır); yön tuşları / PgUp-Dn ile
  fare altındaki parçayı ince kaydır (Shift: 25 cm).

## Uçuş ekranı, eylemler, fırlatma
- Alt ortada **cam kokpit (PFD)**: gaz çubuğu (AB bölgesi, N2) · hız şeridi (km/sa, Mach) · yapay ufuk
  (yunuslama merdiveni, yatış göstergesi) · irtifa şeridi (dikey hız, alçakta yer yüksekliği) · G çubuğu
  (pilot dayanımına göre yeşil/sarı/kırmızı, yapı limiti çizgisi) · pusula.
- **Ses duvarı**: Mach 1 geçilince sentezlenmiş çift çatlamalı sonik patlama, genişleyen şok halkası,
  buhar konisi parlaması ve sarsıntı; ses hızı civarında transonik titreme, ses üstünde boğuk şok gürlemesi.
- **Duman izleri** (füze, fişek, hasar dumanı/alevi, yakıt sızıntısı) kayan orijinle birlikte kayar —
  iz artık birkaç saniye sonra uçağın önünde yeniden belirmez.
- **G sınırlayıcı** (Ayarlar, varsayılan açık): kumanda, pilotun dayanabileceği G'yi aşacak kadar
  çekilemez — yüksek hızda S'ye tam basmak pilotu bayıltmaz. Kumanda yetkisi hıza göre yumuşakça ayarlanır
  ve yunuslama sönümleyici burnun ileri geri sallanmasını önler (akıcı çekiş). Kapatılırsa bayılma gerçekçi süreyle gelir.
- **Fırlatma koltuğu** (⌫ iki kez ya da eylem panelinde FIRLAT'a iki tık): kanopi atılır, pilot
  ~40 m/s fırlar, 1.3 sn sonra paraşüt açılır (≈7 m/s alçalma, A/D W/S ile yönlendirilir). Kamera
  pilotu izler; uçak düşse de pilot kurtulur ve tecrübe kazanır. Paraşüt açılmadan yere çarpan pilot
  (çok alçakta / ters fırlatma) kayıp olur.
- **Uçuşu bitir**: uçak yerde durunca ya da pilot yere inince eylem panelinde çıkar → uçuş raporu
  (süre, görev sonucu, XP, seviye) → Hangar · Tekrar uç · Ana menü. Görev başarıyla bittiğinde uçak
  havadaysa sonuç ekranında **Pilot indirsin** (en yakın meydana otomatik iniş, sonra rapor).
- **Füze** kilit olmadan da atılabilir: uçuşta önündeki koniyi tarar, ısı kaynağı bulursa kilitlenir,
  yoksa boşa gider.

## Silahlar ve savaş
- Solda **SAVAŞ PANELİ** (kenardaki sekmeyle katla): MASTER ARM, flare, silah kartları (tıkla ya da V), kilit
  durumu, radar, **YAPI** şeması (parçalar yüke göre yeşil→kırmızı, G ve tahmini yapı limiti).
- **MASTER ARM** açıkken (kumanda paneli) kokpit HUD'unda nişangahlar: **TOP** — mermi düşüşü ve hedef
  hareketini hesaplayan pipper + öngörü elması (üst üste gelince "ATEŞ"); **FÜZE** — arayıcı halkası,
  kilitlenince hedefe atlar, kilit tonu / arayıcı hırıltısı; **BOMBA** — CCIP (bomba şimdi bırakılsa
  düşeceği nokta, hedef yarıçapındaysa "BIRAK").
- Radar varsa: hedef kutuları (mesafe, yaklaşma hızı, ekran dışı oku) ve sol altta radar ekranı.
- **Füze uyarısı**: sana kilitli füze gelince ok + bip + "Missile". **O** ile flare at: füzenin
  arayıcısı sıcak fişeğe kayabilir. Art yakıcı ısı izini büyütür.
- Düşman yapay zekası: devriye → takip (öncülü nişan, kafa kafaya yana açılma, yo-yo) → füzeden
  kaçış (dik dönüş, gaz kesme, flare); yere çarpmaz, G sınırını aşmaz. `skill` 0..1.
- Yeni parçalar: J-40 hafif / J-120 ağır motor, delta kanat, dümen, flare fişekliği, 250 kg bomba,
  harici yakıt tankı. Örnek uçak: **Şahin-B** (Yükle → Şahin-B).

## Kumanda paneli
Pistte **soğuk ve karanlık** başlarsın: **BATARYA** (ekranlar/HUD yanar) → **JFS** (marş türbini
devir alır) → **MOTOR ÇALIŞTIR** (motor ~7 sn'de rölantiye oturur, JFS kendiliğinden kapanır).
**I** tuşu bu sırayı otomatik yapar.
- Kokpitte fareyle 3B anahtarlara tıklanır; dış kameralarda aynı panel ekranın sağında açılır.
- Kırmızı **kapaklı** anahtarlar (MASTER ARM, YAKIT KES): ilk tık kapağı açar, ikinci tık çalıştırır.
- Işıklı basmalı düğmeler: JFS, MOTOR ÇALIŞTIR, KANOPİ, OTOPİLOT, KOKPİT IŞIĞI.

## Dünya
- **Küre gezegen**, yarıçap 600 km. Yerçekimi merkeze doğru; 70 km'de uzay.
- Küp-küre quadtree LOD arazi: kıtalar, okyanuslar, sıradağlar, ormanlar, köyler.
- Gece/gündüz gezegenin dönüşüyle oluşur (bir gün = 2 saat gerçek zaman). Doğuya uçarsan gün doğumuna yetişirsin.
- Hacimsel bulutlar (içinden geçilir), hava durumları, rüzgar/türbülans, yağmur, şimşek.
- Dalgalı okyanus; su fiziği: kaldırma, su direnci, suya çarpma hasarı.

## Hasar
Her parçanın canı ve yapısal dayanımı var. Aşırı G ya da aşırı hava yükü (ör. yüksek hızda
açılan iniş takımı) parçayı zorlar; dayanımın %60 üstü anında kopartır ("OVER G" uyarısı).
Çarpışmada temas eden parça hasar alır; canı biten parça kopar
ve ona bağlı parçalar da onunla birlikte enkaz olarak düşer. Kalan uçağın kütlesi, ağırlık
merkezi ve aerodinamiği anında değişir. Kokpit yok olursa pilot kaybedilir.

## Test
```
# Otomatik kalkış testi (başsız, telemetri yazdırır)
Godot.exe --headless --path . --fixed-fps 60 -- --autotest
# Marş ve G testleri
Godot.exe --headless --path . --fixed-fps 60 -- --starttest
Godot.exe --headless --path . --fixed-fps 60 -- --air --alt=3000 --gtest --speed=420
# Çarpışma testi (kara / su)
Godot.exe --headless --path . --fixed-fps 60 -- --air --alt=120 --crashtest
Godot.exe --headless --path . --fixed-fps 60 -- --air --alt=120 --x=40000 --crashtest
# Hangar: fareyle sıfırdan uçak kur, sonra kalkış testi
Godot.exe --path . -- --hangar --hangartest --autotest
# İt dalaşı (iki yapay zeka; --dumb: bizimki pasif), top isabet, görev testi
Godot.exe --headless --path . --fixed-fps 60 -- --air --alt=3000 --dogfight --duration=120
Godot.exe --headless --path . --fixed-fps 60 -- --air --alt=3000 --guntest --dist=500
Godot.exe --headless --path . --fixed-fps 60 -- --mission=it --missiontest --aiplayer
Godot.exe --headless --path . -- --autolandtest [--af=1]        # otomatik iniş
Godot.exe --headless --path . -- --air --pulltest --v=290 [--nolimit]   # yüksek hızda S: G sınırlayıcı
Godot.exe --headless --path . -- --air --alt=300 --ejecttest       # fırlatma + paraşüt + iniş
Godot.exe --headless --path . -- --air --loaltest [--straight]    # kilitsiz füze atışı
# Ekran görüntüsü
Godot.exe --path . -- --air --alt=25000 --hour=18 --weather=3 --camera=1 --screenshot=C:/yol/shot.png --shot-time=5
```
Diğer argümanlar: `--x=metre` (doğuya kaydır), `--eva`, `--lights`, `--debug`, `--nohelp`, `--yaw=derece`.

## Yapı
```
core/           Game (tuşlar), Planet (küre, güneş), FloatingOrigin (3B), Weather (hava + saat), Atmosphere
vessel/         Vessel (tek RigidBody, hasar, kopma), Part, Debris, Hydro (su), MeshFactory, VesselLights
  modules/      wing, control_surface, engine (afterburner), fuel_tank, body_drag, landing_gear, cockpit
cockpit/        CockpitSwitch (tıklanabilir), MfdDisplay (canlı ekranlar)
pilot/          PilotModel (IK'li pilot), PilotCharacter (EVA)
parts/          PartLibrary — parça tanımları
crafts/         uçaklar (JSON). "mirror": true simetrik kopyasını ekler
world/          SkyController, VolumetricClouds, Effects, Airfield, gök/su/bulut shader'ları
  terrain/      TerrainGen (yükseklik), Terrain (küp-küre LOD), TerrainChunkJob, TerrainCollision, TerrainProps
camera/ controls/ ui/ audio/ debug/ tests/
```
