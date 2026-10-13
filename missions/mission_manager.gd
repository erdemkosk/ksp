class_name MissionManager
extends Node
## Görevler: tanımlar, kurulum (düşmanlar, halkalar, hedefler), hedef takibi, ekran listesi,
## yön işareti ve sonuç ekranı. Game.mission = görev kimliği (boşsa serbest uçuş).
##
## Konumlar havaalanına göre "yüzey koordinatı" ile verilir: x doğu, z güney (metre),
## irtifa deniz seviyesinden ya da yerden (agl). Pist z≈0..1100, x=0 boyunca kuzey-güney.

const DEFS := [
	{"id": "egitim", "title": "Eğitim Uçuşu", "level": 1,
		"brief": "Kalkış yap, dört halkadan sırayla geç ve piste geri in. Halkalar 400-900 m irtifada. Uçak tamamen durunca görev biter.",
		"start": "runway"},
	{"id": "kesif", "title": "Keşif", "level": 1,
		"brief": "Üç keşif noktasının üzerinden yerden 600 m'nin altında geç (fotoğraf). Sonra üsse dön: havaalanının 3 km yakınına gel.",
		"start": "runway_hot"},
	{"id": "kara", "title": "Kara Saldırısı", "level": 2,
		"brief": "Ovaköy yolunda kuzeybatıya ilerleyen 6 araçlık düşman konvoyunu yok et. Konvoyu iki uçaksavar topu koruyor (3 km, alçak uçarken tehlikeli) ve üstünde bir düşman avcı devriye uçuyor. Bomba (V ile BOMBA, CCIP) ya da top kullan.",
		"start": "air", "alt": 1500.0, "z": 6000.0},
	{"id": "onleme", "title": "Önleme (Alarm Kalkışı)", "level": 2,
		"brief": "İki düşman bombardıman uçağı kuzeyden üsse geliyor! Hemen kalk ve ikisini de üsse 3 km yaklaşmadan düşür. Bombardımanlar savunmasız ama flare atar.",
		"start": "runway_hot", "time": 300.0},
	{"id": "it", "title": "İt Dalaşı", "level": 3,
		"brief": "Bire bir: deneyimli bir düşman pilotu 6 km önünde, sana doğru geliyor. Füzesi ve topu var, füzelerine flare at (O). Onu düşür.",
		"start": "air", "alt": 3000.0, "z": 0.0},
	{"id": "yolcu", "title": "Yolcu Turu (sivil)", "level": 1,
		"brief": "6 yolcuyu manzara turuna çıkar: iki seyir noktasının 1 km yakınından geç, sonra üsse in ve dur. Konforlu uç: yatış 35°'den az, G 0.4–1.8 arası, yumuşak iniş. Konfor %40'ın altına düşerse görev biter. Gerekli: 6 koltuk (örn. Kırlangıç).",
		"start": "runway_hot", "civil": true},
	{"id": "tasima", "title": "Kuzey Seferi (yolcu, A→B)", "level": 2,
		"brief": "6 yolcuyu Ana Üs'ten Kuzey Havaalanı'na (~30 km kuzeybatı) götür. Yolda Ovaköy'ün üzerinden geç (1.5 km), konforlu uç ve Kuzey Havaalanı pistine in, dur. Gerekli: 6 koltuk (örn. Kırlangıç).",
		"start": "runway_hot", "civil": true},
	{"id": "kurtarma", "title": "Kurtarma", "level": 2,
		"brief": "Üç kazazede üsten ~10 km uzakta, dumanın yanında bekliyor. Yanlarına (250 m) in, dur ve binmelerini bekle, sonra üsse getir. Gerekli: yolcu kabini (örn. Kırlangıç). Fren paraşütü ve hava freni kısa inişe yardım eder.",
		"start": "runway_hot", "civil": true},
	{"id": "kargo", "title": "Yardım Bırakma", "level": 2,
		"brief": "Selden etkilenen köye yardım: sandıkları turuncu bölgeye (150 m) paraşütle bırak, en az 3 tanesi bölgeye inmeli. V ile KARGO'yu seç; sarı halka sandığın ineceği yer, Space bırakır. Gerekli: kargo bölmesi (örn. Katır).",
		"start": "runway_hot", "civil": true},
	{"id": "nakliye", "title": "Ağır Nakliye (kargo, A→B)", "level": 2,
		"brief": "Kuzey Havaalanı'ndaki birliğe malzeme götür: en az 8 sandık kargoyla Ana Üs'ten kalk, Kuzey Havaalanı'na (~30 km kuzeybatı) in ve dur. Yer ekibi sandıkları tek tek boşaltır (uçak durmalı). Ağır yüklü uçak uzun koşuyla kalkar, geç döner — yumuşak in. Gerekli: kargo bölmeleri (örn. Herkül C-130).",
		"start": "runway_hot", "civil": true},
	{"id": "heli", "title": "Helikopter Avı", "level": 2,
		"brief": "İki düşman saldırı helikopteri Dereköy (~23 km kuzey) çevresinde alçakta devriye geziyor. İkisini de düşür. Helikopterler radarda görünmez, yavaş ve alçaktır; yaklaşırsan sana dönüp topla ateş ederler.",
		"start": "air", "alt": 1200.0, "z": -6000.0},
	{"id": "ikmal", "title": "Havada İkmal", "level": 2,
		"brief": "Yakıtın azaldı. Önündeki tanker (Deve) düz uçuyor, arkasından ikmal hortumu sarkıyor. Arkasına geç, hızını eşle ve probu yavaşça sepete sok (en çok 6 m/s yaklaşma). Bağlıyken pozisyonu koru: 1500 kg yakıt al, sonra üsse dön. Gerekli: havada ikmal probu (burnun yanına/üstüne takılır).",
		"start": "air", "alt": 2600.0, "z": 3000.0},
	{"id": "sam", "title": "Hava Savunmasını Kır", "level": 3,
		"brief": "Dereköy'ün güneyindeki iki SAM rampası bölgeyi kapatıyor. 9 km içinde ve yerden 120 m üstünde görünürsen radar kilitlenir ve radar güdümlü füze atar (RWR'da S). Vadilerde alçak uç (arazi radarı keser), rampaya dik uç (çentik: Doppler radarı seni kaybeder) ya da füze yaklaşınca chaff at (O). Rampaları uçaksavar topları koruyor. İki SAM'ı da yok et.",
		"start": "air", "alt": 900.0, "z": -4000.0},
	{"id": "ustunluk", "title": "Hava Üstünlüğü", "level": 3,
		"brief": "Üç düşman avcı iki dalga hâlinde geliyor: önce bir, sonra iki. Hepsini düşür ve hayatta kal.",
		"start": "air", "alt": 2500.0, "z": 2000.0},
	{"id": "sead", "title": "SEAD — SAM Avı", "level": 3,
		"brief": "Kuzeyde uzun menzilli bir SAM bataryası (40 km: fırlatıcı + arama radarı + takip radarı), iki kısa menzilli SAM ve bir erken uyarı radarı hava sahasını kapatıyor. Bütün radarları ve rampaları yok et. Radar avcısı füze (HARM) yayına kilitlenir: arama radarı ölürse batarya kör kalır, takip radarı ölürse füze atamaz. Alçaktan, araziye saklanarak yaklaş (Shift+U: arazi takibi), chaff (Ş) ve ECM işe yarar.",
		"start": "air", "alt": 3000.0, "z": 16000.0},
	{"id": "derin", "title": "Derin Saldırı", "level": 3,
		"brief": "Kuzeybatıdaki üç mühimmat deposunu yok et ve üsse dön. Yolda bir erken uyarı radarı var: seni görürse düşman üssü avcı kaldırır ve bir AWACS seni izler. Radarın altından gir: yerden 100 m'de vadileri izle (Shift+U), dağların arkasında kal. HUD'daki GÖRÜNÜYORSUN / GİZLİ ışığına bak. Hedefte uçaksavar ve omuzdan atılan SAM'lar (RWR'da görünmez!) var: flare (O) hazır tut.",
		"start": "air", "alt": 600.0, "z": 2000.0},
	{"id": "ussaldiri", "title": "Havaalanı Baskını", "level": 3,
		"brief": "Kuzeydeki düşman havaalanını devre dışı bırak: pistin üç bölümünden en az ikisini kes (1000 kg bomba, misket ya da bomba bölmesi) ve park etmiş uçaklarla hangarlardan beşini yok et. Alarm verilince pist sağlamsa avcılar kalkar — önce pisti kes. Üssü uçaksavar, SAM ve omuzdan atılan SAM'lar koruyor; erken uyarı radarı yaklaşanı görür.",
		"start": "air", "alt": 900.0, "z": -2000.0},
	{"id": "uzak", "title": "Uzaktan Vuruş", "level": 3,
		"brief": "Haritanın kuzeybatı köşesindeki komuta sığınağını uzaktan vur. Sığınağı uzun menzilli bir SAM (40 km) koruyor: içine girme. Seyir füzesi (110 km) ya da süzülen bomba (yüksekten 25–40 km) gerekir: haritayı aç (M), sığınağa sol tıkla (GPS hedefi), menzildeyken bırak. SAM seyir füzesini de vurabilir — iki füze at ya da arazinin arkasından yaklaştır.",
		"start": "air", "alt": 7000.0, "z": 15000.0},
	{"id": "deniz", "title": "Deniz Saldırısı", "level": 3,
		"brief": "Kıyı açığında iki düşman korveti seyrediyor. Her birinin arama radarı (30 km, RWR'da G), radar güdümlü SAM'ı (12 km) ve yakın savunma topları (gelen füzeyi de düşürebilir) var. Gemi savar füze (70 km) en iyisi: denizin 15 m üstünde uçar, hedefe yaklaşınca kendi radarını açar. İki gemiyi de batır.",
		"start": "air", "alt": 1500.0, "z": 2000.0},
	{"id": "filo", "title": "Filo Baskını", "level": 3, "bonus": 15000,
		"brief": "Düşman uçak gemisi kuzeydoğu açıklarında bir muhrip ve bir korvetin refakatinde seyrediyor. Gemi seni radarıyla (45 km, RWR'da CV) 28 km içinde görürse ya da alarm alırsa güvertesinden avcı kaldırır (havada en çok iki). Muhribin 76 mm topu 6.5 km içinde uçaksavar mermisi atar, SAM'ları 16 km. Uçak gemisini batır: çok sayıda gemi savar füzesi (70 km) ya da ağır bomba gerekir. Refakatleri batırmak şart değil ama önce onları susturmak işini kolaylaştırır.",
		"start": "air", "alt": 1500.0, "z": 2000.0},
	{"id": "firkateyn", "title": "Fırkateyn Avı", "level": 3, "bonus": 5000,
		"brief": "Dereköy açıklarında iki düşman fırkateyni devriye geziyor. Her birinin arama radarı (40 km, RWR'da DD), 16 radar güdümlü SAM'ı (16 km), iki yakın savunma topu ve 6.5 km menzilli 76 mm baş topu var. Gemi savar füzeyi menzil dışından at, iki füze at (CIWS birini düşürebilir); yaklaşman gerekirse denizin üstünde alçak uç. İki fırkateyni de batır.",
		"start": "air", "alt": 1500.0, "z": -2000.0},
	{"id": "devriye", "title": "Deniz Devriyesi", "level": 2,
		"brief": "Üç düşman akıncı korveti kuzeydoğudan Güney Sahili'ne doğru iniyor; kıyıya ulaşırlarsa limanı topa tutacaklar. Hepsini kıyıya (turuncu nokta, 3 km) varmadan batır. Korvetlerin radarı 30 km, SAM'ı 12 km, CIWS'leri gelen füzeyi düşürebilir. Gemi savar füze ya da bomba kullan.",
		"start": "air", "alt": 1500.0, "z": 2000.0},
	{"id": "sondarbe", "title": "Son Darbe", "level": 3, "bonus": 20000,
		"brief": "Düşman karargâhı Kuzey Havaalanı'nın (~30 km kuzeybatı) üzerinde Kara Doğan ve iki eskortu devriye uçuyor. Kara Doğan'ı düşür: bu sefer kaçmayacak. Eskortlar isteğe bağlı. Onu yüksekte ve süratte yenmek zor; uçağını ona göre tasarla.",
		"start": "air", "alt": 4500.0, "z": -2000.0},
]

const RING_RADIUS := 55.0
const SAHIN_B := "res://crafts/sahin_b.json"
const SAM_SITES := [Vector2(5300, -19600), Vector2(7400, -20600)]
const TANKER_SPEED := 135.0
const REFUEL_GOAL := 1500
const LR_SAM := Vector2(-6000, -24000)
const EW_SITE := Vector2(-6000, -27500)
const DEPOTS := [Vector2(-21000, -17000), Vector2(-21800, -17600), Vector2(-20400, -17900)]
const BUNKER := Vector2(-30000, -27000)

var _airbase: EnemyAirbase

var main: Node
var def := {}
var objectives: Array[Dictionary] = []    # {text, done}
var nav_point: Variant = null             # dünya konumu (yön işareti)
var nav_label := ""
var state := "running"                    # running / success / fail
var fail_reason := ""
var money_gain := 0
var _await_landing := false
var elapsed := 0.0
var kills := 0

var _enemies: Array[Vessel] = []
var _rings: Array[MeshInstance3D] = []
var _ring_index := 0
var _points: Array[Vector3] = []          # yüzey koordinatları (x, irtifa, z) — keşif
var _wave := 0
var _ui: Control
var _result: PanelContainer
var _font: SystemFont
var _bold: SystemFont
var _was_airborne := false
var _pending_fail := ""
var _site := Vector3.ZERO        # yüzey koordinatı (x, yer yüksekliği, z)
var _phase := 0
var _wait := 0.0
var _comfort := 100.0
var _last_vs := 0.0
var _airborne_t := 0.0
var _inside := 0
var _tanker: Vessel
## Üretilmiş görev (Game.mission = "gen") ve alışkanlık / sonuç kaydı
var gen: GenMission
var tracker: Doctrine.Tracker


static func get_def(id: String) -> Dictionary:
	if id == "gen":
		return MissionGen.def_for(GenMission.card_now())
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}


## Yüzey koordinatından dünya konumu: x doğu, z güney, alt deniz seviyesinden.
static func world_point(x: float, z: float, alt: float) -> Vector3:
	var dir := Vector3(x, Planet.RADIUS, z).normalized()
	return Planet.center() + dir * (Planet.RADIUS + alt)


static func ground_height(x: float, z: float) -> float:
	return maxf(TerrainGen.height(Vector3(x, Planet.RADIUS, z).normalized()), 0.0)


# ------------------------------------------------------------------ kurulum

func _ready() -> void:
	def = get_def(Game.mission)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)


## main.gd, uçak doğduktan sonra çağırır.
func setup() -> void:
	if not def.is_empty():
		tracker = Doctrine.Tracker.new()
		tracker.mm = self
		add_child(tracker)
	match def.get("id", ""):
		"gen":
			gen = GenMission.new(self)
			gen.setup()
		"egitim":
			objectives = [_obj("Kalkış yap"), _obj("Halkalardan geç (0/4)"), _obj("Piste in ve dur")]
			var ring_pts := [Vector3(-1500, 500, -4500), Vector3(2500, 800, -7500), Vector3(5500, 900, -3500), Vector3(2500, 450, 3500)]
			for i in ring_pts.size():
				var p: Vector3 = ring_pts[i]
				var nxt: Vector3 = ring_pts[i + 1] if i + 1 < ring_pts.size() else Vector3(0, 300, 6000)
				_add_ring(p, nxt - p)
		"kesif":
			objectives = [_obj("Keşif noktası A"), _obj("Keşif noktası B"), _obj("Keşif noktası C"), _obj("Üsse dön")]
			_points = [Vector3(-6000, 0, -9000), Vector3(4000, 0, -16000), Vector3(9000, 0, -5000)]
		"kara":
			objectives = [_obj("Konvoyu yok et (0/6)"), _obj("Hayatta kal")]
			_clear_static_targets()
			var road: Array[Vector2] = []
			for p: Vector2 in Towns.ROADS[0]:
				road.append(p)
			for i in 6:
				_add_unit(ConvoyTruck.create_truck(road, 2400.0 - i * 32.0, i % 2 == 0))
			for k in [2100.0, 2900.0]:
				_add_unit(AaaGun.create_aaa(Vector3.ZERO, 0.0), _road_point(road, k) + Vector2(70, -40))
			_spawn_enemy(Vector3(-1500, 2200, -3500), 90.0, 0.45, false, "Düşman Devriye")
		"heli":
			objectives = [_obj("Helikopterler (0/2)"), _obj("Hayatta kal")]
			for i in 2:
				var h := Helicopter.create_heli("attack")
				h.home_xz = Vector2(6000 + i * 1200, -21000 - i * 900)
				h._patrol_a = i * PI
				_add_unit(h, h.home_xz + Vector2(1500, 0), 120.0)
		"sam":
			objectives = [_obj("SAM rampaları (0/2)"), _obj("Hayatta kal")]
			_clear_static_targets()
			for p: Vector2 in SAM_SITES:
				_add_unit(SamSite.create_sam(Vector3.ZERO, 0.0), p)
			for p: Vector2 in [Vector2(5600, -19200), Vector2(6900, -20900), Vector2(6200, -20200)]:
				_add_unit(AaaGun.create_aaa(Vector3.ZERO, 0.0), p)
		"ikmal":
			objectives = [_obj("Tankere bağlan"), _obj("Yakıt al (0/%d kg)" % REFUEL_GOAL), _obj("Üsse dön (3 km)")]
			if main.vessel.probe() == null:
				_pending_fail = "Uçakta havada ikmal probu yok (hangarda 'Havada İkmal Probu' tak)"
			else:
				# yakıt %25'e iner: ikmal gerçekten gerekli
				for m in main.vessel.modules:
					if m is FuelTankModule:
						m.fuel = m.capacity * 0.25
				main.vessel.recalc_mass()
				_spawn_tanker(Vector3(0, 2600, 3000 - 1800))
		"sead":
			objectives = [_obj("SAM radarları ve rampaları (0/7)"), _obj("Hayatta kal")]
			_clear_static_targets()
			var lr := SamSite.create_long_range()
			_add_unit(lr[0], LR_SAM)
			_add_unit(lr[1], LR_SAM + Vector2(70, 30))
			_add_unit(lr[2], LR_SAM + Vector2(-55, 40))
			for p: Vector2 in [Vector2(-3000, -20000), Vector2(-9500, -21000)]:
				_add_unit(SamSite.create_sam(Vector3.ZERO, 0.0), p)
				_add_unit(AaaGun.create_aaa(Vector3.ZERO, 0.0), p + Vector2(300, 200))
			_add_unit(RadarStation.create_station(), EW_SITE)
			_add_unit(Manpads.create_team(), Vector2(-4500, -18000))
		"derin":
			objectives = [_obj("Mühimmat depoları (0/3)"), _obj("Üsse dön (3 km)")]
			_clear_static_targets()
			var ew := RadarStation.create_station()
			_add_unit(ew, Vector2(-3000, -15000))
			for i in DEPOTS.size():
				var dp := _depot()
				_add_unit(dp, DEPOTS[i])
			_add_unit(SamSite.create_sam(Vector3.ZERO, 0.0), DEPOTS[1] + Vector2(500, 300))
			for p: Vector2 in [DEPOTS[0] + Vector2(250, -200), DEPOTS[2] + Vector2(-200, 250)]:
				_add_unit(AaaGun.create_aaa(Vector3.ZERO, 0.0), p)
			for p: Vector2 in [DEPOTS[0] + Vector2(-600, 900), DEPOTS[2] + Vector2(800, -400), Vector2(-9000, -14000)]:
				_add_unit(Manpads.create_team(), p)
			_airbase = EnemyAirbase.build(self, Vector2(-26000, -27000), Vector2(-17000, -21000), 31)
			ew.spotted.connect(func(_v: Vessel) -> void: _airbase._on_alert())
			_spawn_awacs(Vector3(-6000, 6500, -29000))
		"ussaldiri":
			objectives = [_obj("Pisti kes (0/2 bölüm)"), _obj("Uçak ve hangar (0/5)"), _obj("Hayatta kal")]
			_clear_static_targets()
			_airbase = EnemyAirbase.build(self, Vector2(-18000, -29000), Vector2(-6000, -20000), 53)
		"uzak":
			objectives = [_obj("Komuta sığınağını yok et"), _obj("Uzun menzilli SAM'a (40 km) girme")]
			_clear_static_targets()
			var bk := _depot("Komuta sığınağı", 2400.0)
			_add_unit(bk, BUNKER)
			var lr2 := SamSite.create_long_range()
			_add_unit(lr2[0], BUNKER + Vector2(1800, 1500))
			_add_unit(lr2[1], BUNKER + Vector2(1870, 1530))
			_add_unit(lr2[2], BUNKER + Vector2(1745, 1540))
			for p: Vector2 in [BUNKER + Vector2(300, 200), BUNKER + Vector2(-250, -300)]:
				_add_unit(AaaGun.create_aaa(Vector3.ZERO, 0.0), p)
			var has := false
			for m in main.vessel.modules:
				if (m is MissileModule and m.guidance == "cruise") or (m is BombModule and m.kind == "glide"):
					has = true
			if not has:
				_pending_fail = "Uçakta seyir füzesi ya da süzülen bomba yok (hangarda tak)"
		"deniz":
			objectives = [_obj("Savaş gemileri (0/2)"), _obj("Hayatta kal")]
			var sea := _sea_points(2)
			for i in sea.size():
				var sh := Warship.create_ship("Düşman korveti %d" % (i + 1))
				sh.heading = randf() * TAU
				_add_unit(sh, sea[i])
		"filo":
			objectives = [_obj("Uçak gemisi (0/1)"), _obj("Hayatta kal")]
			for s in NavalGroup.spawn(main.world, "carrier", NavalGroup.FLEET_ROUTE, NavalGroup.FLEET_XZ):
				s.objective = s is Carrier
				if s is Carrier:
					s.launched.connect(func(e: Vessel) -> void: _enemies.append(e))
		"firkateyn":
			objectives = [_obj("Fırkateynler (0/2)"), _obj("Hayatta kal")]
			NavalGroup.spawn(main.world, "destroyers", NavalGroup.HUNT_ROUTE, NavalGroup.HUNT_XZ)
		"devriye":
			objectives = [_obj("Akıncı korvetler (0/3)"), _obj("Kıyıya ulaşmalarına izin verme")]
			var raid_route: Array[Vector2] = [NavalGroup.RAID_XZ, NavalGroup.RAID_GOAL]
			NavalGroup.spawn(main.world, "raiders", raid_route)
			_site = Vector3(NavalGroup.RAID_GOAL.x, 0.0, NavalGroup.RAID_GOAL.y)
			_mark_site(_site, false)
		"onleme":
			objectives = [_obj("Bombardıman 1"), _obj("Bombardıman 2"), _obj("Üssü koru")]
			for i in 2:
				var e := _spawn_enemy(Vector3(-800 + i * 1600, 4000, -26000 - i * 1500), 180.0, 0.5, false, "Bombardıman %d" % (i + 1), SAHIN_B)
				_set_bomber(e)
		"it":
			objectives = [_obj("Düşman asını düşür"), _obj("Hayatta kal")]
			_spawn_enemy(Vector3(0, 3100, -6000), 180.0, 0.75, true, "Düşman As (Şahin)", SAHIN_B)
		"ustunluk":
			objectives = [_obj("1. dalga (0/1)"), _obj("2. dalga (0/2)"), _obj("Hayatta kal")]
			_spawn_wave()
		"yolcu":
			objectives = [_obj("Seyir noktası: Sahil"), _obj("Seyir noktası: Tepeler"), _obj("Üsse in ve dur"), _obj("Konfor %100")]
			_points = [Vector3(7000, 900, -4000), Vector3(-5000, 1100, -11000)]
			var left: int = main.vessel.board_passengers(6)
			if left > 0:
				_pending_fail = "Uçakta 6 yolcu koltuğu yok (yolcu kabini tak)"
		"tasima":
			objectives = [_obj("Ovaköy üzerinden geç"), _obj("Kuzey Havaalanı'na in ve dur"), _obj("Konfor %100")]
			if main.vessel.board_passengers(6) > 0:
				_pending_fail = "Uçakta 6 yolcu koltuğu yok (yolcu kabini tak)"
		"kurtarma":
			objectives = [_obj("Kazazedelerin yanına in"), _obj("Kazazedeleri al (0/3)"), _obj("Üsse dön ve in")]
			_site = _find_flat(7000.0, 12000.0, 11)
			_mark_site(_site, true)
			if main.vessel.passenger_seats() < 3:
				_pending_fail = "Uçakta yolcu kabini yok (en az 3 koltuk)"
		"nakliye":
			_freight_total = main.vessel.cargo_left()
			objectives = [_obj("Kuzey Havaalanı'na in ve dur"), _obj("Yükü boşalt (0/%d)" % _freight_total)]
			if _freight_total < 8:
				_pending_fail = "Uçakta en az 8 sandık kargo yok (kargo bölmesi tak — örn. Herkül)"
		"kargo":
			objectives = [_obj("Sandıklar bölgede (0/3)")]
			_site = _find_flat(7000.0, 12000.0, 23)
			_mark_site(_site, false)
			if main.vessel.cargo_left() < 3:
				_pending_fail = "Uçakta kargo bölmesi yok (en az 3 sandık)"
			else:
				main.vessel.selected_weapon = Vessel.WEAPON_CARGO
	_message("GÖREV: " + def.get("title", ""), 4.0)
	Ace.attach(self)   # düşman ası (Campaign: kameo / av / final)


func _obj(text: String) -> Dictionary:
	return {"text": text, "done": false}


func _spawn_enemy(p: Vector3, heading_deg: float, skill: float, aggressive: bool, title: String, craft_path := "") -> Vessel:
	var pos := world_point(p.x, p.z, p.y)
	var frame := Planet.local_basis(pos)
	# yön: 0 = kuzey (-z), 90 = doğu; local_basis x doğu, z güney
	var basis := Basis(frame.y, deg_to_rad(-heading_deg)) * frame
	var craft := VesselBuilder.load_craft(craft_path if craft_path != "" else main.CRAFT_PATH)
	craft["paint"] = {"scheme": "çöl" if craft_path == "" else "gece", "number": "D-%d" % (10 + randi() % 80)}
	var e := VesselBuilder.build(craft)
	e.name = "Enemy%d" % _enemies.size()
	e.craft_name = title
	e.team = "düşman"
	e.transform = Transform3D(basis, pos)
	e.linear_velocity = -basis.z * 210.0
	main.world.add_child(e)
	e.set_gear_instant(false)
	e.set_hot()
	e.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = e
	ai.skill = skill
	ai.aggressive = aggressive
	ai.altitude = p.y
	ai.speed = 210.0
	ai.leg_time = 60.0
	e.add_child(ai)
	_enemies.append(e)
	return e


## Mühimmat deposu / sığınak: yarı gömülü beton yapı (hedef).
func _depot(title := "Mühimmat deposu", hp_value := 1500.0) -> GroundTarget:
	var d := RadarStation.make_truck(title, hp_value)
	for c in d.get_children():
		c.queue_free()
	var bunker := title != "Mühimmat deposu"
	d._hull = GroundTarget._mesh(d, Vector3(22, 6, 14) if bunker else Vector3(18, 5, 30), Vector3(0, 2.5, 0), Color(0.5, 0.5, 0.46) if bunker else Color(0.36, 0.4, 0.3))
	var roof := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0 if bunker else 9.0
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 22.0 if bunker else 30.0
	roof.mesh = cyl
	roof.rotation_degrees = Vector3(0, 0, 90) if bunker else Vector3(90, 0, 0)
	roof.scale = Vector3(1, 1, 0.35)
	roof.position = Vector3(0, 5.0, 0)
	roof.material_override = SamSite._mat(Color(0.42, 0.45, 0.36))
	d.add_child(roof)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(22, 9, 30)
	cs.shape = box
	cs.position = Vector3(0, 4.5, 0)
	d.add_child(cs)
	return d


## Düşman AWACS: yüksekte yarış pisti çizer, 80 km'de gördüğünü takımına bildirir.
func _spawn_awacs(p: Vector3) -> Vessel:
	var e := _spawn_enemy(p, 90.0, 0.4, false, "Düşman AWACS", "res://crafts/awacs.json")
	e.set_meta("awacs", true)
	for c in e.get_children():
		if c is AIPilot:
			c.leg_time = 120.0
			c.speed = 150.0
	return e


## Haritada derin deniz noktaları (kıyıdan uzak, birbirine ~3 km), üsten en az 15 km.
static func _sea_points(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in 3000:
		var p := Vector2(rng.randf_range(FlightMap.WORLD_LO.x, FlightMap.WORLD_HI.x), rng.randf_range(FlightMap.WORLD_LO.y, FlightMap.WORLD_HI.y))
		if p.length() < 15000.0 or TerrainGen.height(Vector3(p.x, Planet.RADIUS, p.y).normalized()) > -30.0:
			continue
		if out.is_empty() or (p.distance_to(out[0]) > 2000.0 and p.distance_to(out[0]) < 6000.0):
			out.append(p)
		if out.size() >= n:
			break
	if out.is_empty():
		out.append(Vector2(15000, 8000))
	while out.size() < n:
		out.append(out[0] + Vector2(3000, 0))
	return out


## Dost tanker: Katır gövdesi, sivil boya, kuzeye düz ve sabit hızla uçar; uzun ayaklarla
## yarış pisti çizer. Arkasına ikmal hortumu (Drogue) takılır.
func _spawn_tanker(p: Vector3) -> void:
	var pos := world_point(p.x, p.z, p.y)
	var frame := Planet.local_basis(pos)
	var craft := VesselBuilder.load_craft("res://crafts/katir.json")
	craft["paint"] = {"scheme": "kırmızı-beyaz", "number": "T-01"}
	var t := VesselBuilder.build(craft)
	t.name = "Tanker"
	t.craft_name = "Tanker Deve"
	t.team = main.vessel.team
	t.transform = Transform3D(frame, pos)       # burun kuzeye (-z)
	t.linear_velocity = -frame.z * TANKER_SPEED
	main.world.add_child(t)
	t.set_gear_instant(false)
	t.set_hot()
	t.lights_on = true
	var ai := AIPilot.new()
	ai.vessel = t
	ai.aggressive = false
	ai.altitude = p.y
	ai.speed = TANKER_SPEED
	ai.leg_time = 240.0
	t.add_child(ai)
	_tanker = t
	Drogue.attach(t)


func _check_refuel(v: Vessel) -> void:
	var probe := v.probe()
	if probe == null:
		return
	if not is_instance_valid(_tanker) or _tanker.parts.is_empty():
		_finish(false, "Tanker kaybedildi")
		return
	if not objectives[0]["done"]:
		nav_point = _tanker.com_global()
		nav_label = "TANKER"
		if probe.connected():
			objectives[0]["done"] = true
			_message("Bağlandın! Pozisyonu koru.", 3.0)
		return
	if not objectives[1]["done"]:
		nav_point = _tanker.com_global()
		nav_label = "TANKER"
		objectives[1]["text"] = "Yakıt al (%d/%d kg)" % [mini(int(probe.received), REFUEL_GOAL), REFUEL_GOAL]
		if probe.received >= REFUEL_GOAL:
			objectives[1]["done"] = true
			_message("Yakıt tamam — ayrıl ve üsse dön.", 4.0)
		return
	nav_point = world_point(0, 600, 300.0)
	nav_label = "ANA ÜS"
	if _near_base(v, 3000.0):
		objectives[2]["done"] = true
		_finish(true, "İkmal tamamlandı")


## Bombardıman: üsse doğru düz uçar (devriye, dönmez).
func _set_bomber(e: Vessel) -> void:
	for c in e.get_children():
		if c is AIPilot:
			c.leg_time = 99999.0
			c.speed = 190.0


func _spawn_wave() -> void:
	_wave += 1
	if _wave == 1:
		_spawn_enemy(Vector3(0, 2600, -9000), 180.0, 0.45, true, "Düşman 1")
	else:
		# kol: lider + sağ arkasında kanat adamı (birlikte saldırır, birbirini korur)
		var lead := _spawn_enemy(Vector3(-2000, 3000, -11000), 160.0, AIPilot.LEVELS["tecrübeli"], true, "Düşman 2")
		var wing := _spawn_enemy(Vector3(-2380, 3040, -11020), 160.0, 0.6, true, "Düşman 3 (Şahin)", SAHIN_B)
		AIPilot.pair(lead, wing)
		_message("2. DALGA: iki düşman kol hâlinde kuzeyden geliyor!", 4.0)


func _add_ring(surface: Vector3, dir_surface: Vector3) -> void:
	var g := ground_height(surface.x, surface.z)
	var pos := world_point(surface.x, surface.z, g + surface.y)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = RING_RADIUS - 4.0
	t.outer_radius = RING_RADIUS + 4.0
	t.rings = 48
	t.ring_segments = 12
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.2)
	m.emission_enabled = true
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.world.add_child(ring)
	ring.global_position = pos
	# halka düzlemi uçuş yönüne dik: torusun ekseni (y) uçuş yönü
	var frame := Planet.local_basis(pos)
	var fly := (frame.x * dir_surface.x + frame.z * dir_surface.z).normalized()
	var bx := frame.y.cross(fly).normalized()
	ring.global_basis = Basis(bx, fly, bx.cross(fly))
	_rings.append(ring)


# ------------------------------------------------------------------ döngü

func _physics_process(delta: float) -> void:
	if _await_landing:
		_wait_landing()
		return
	if def.is_empty() or state != "running":
		return
	var v: Vessel = main.vessel
	if not is_instance_valid(v):
		return
	elapsed += delta
	if v.cockpit() == null or not v.has_pilot() and not is_instance_valid(main.pilot):
		_finish(false, "Pilot kaybedildi")
		return
	if not _pending_fail.is_empty():
		_finish(false, _pending_fail)
		return
	_count_kills()
	match def["id"]:
		"egitim":
			_check_training(v)
		"kesif":
			_check_recon(v)
		"kara":
			_check_ground(v)
		"heli":
			_check_units(v, "Helikopterler", "HELİKOPTER", func(n: Node) -> bool: return n is Helicopter)
		"sam":
			_check_units(v, "SAM rampaları", "SAM", func(n: Node) -> bool: return n is SamSite)
		"ikmal":
			_check_refuel(v)
		"sead":
			_check_units(v, "SAM radarları ve rampaları", "SAM", func(n: Node) -> bool:
				return n is SamSite or n is RadarStation or String(n.unit_name).begins_with("SAM"))
		"derin":
			_check_deep(v)
		"ussaldiri":
			_check_airbase(v)
		"uzak":
			_check_standoff(v)
		"deniz":
			_check_units(v, "Savaş gemileri", "GEMİ", func(n: Node) -> bool: return n is Warship)
		"filo":
			_check_units(v, "Uçak gemisi", "UÇAK GEMİSİ", func(n: Node) -> bool: return n is Carrier)
		"firkateyn":
			_check_units(v, "Fırkateynler", "FIRKATEYN", func(n: Node) -> bool: return n is Frigate)
		"devriye":
			_check_raid(v)
		"onleme":
			_check_intercept(v)
		"it":
			_check_dogfight(v)
		"ustunluk":
			_check_superiority(v)
		"yolcu":
			_check_passengers(v, delta)
		"tasima":
			_check_transfer(v, delta)
		"kurtarma":
			_check_rescue(v, delta)
		"kargo":
			_check_cargo(v)
		"nakliye":
			_check_freight(v, delta)
		"gen":
			gen.check(v, delta)
	if def.has("time") and elapsed > def["time"] and state == "running":
		_finish(false, "Süre doldu")


## Derin saldırı: üç depo, sonra üsse dönüş.
func _check_deep(v: Vessel) -> void:
	if not objectives[0]["done"]:
		var dead := 0
		var nearest: Variant = null
		var nd := INF
		for n in main.world.get_children():
			if n is GroundTarget and n.unit_name == "Mühimmat deposu":
				if n.destroyed:
					dead += 1
				elif n.global_position.distance_to(v.com_global()) < nd:
					nd = n.global_position.distance_to(v.com_global())
					nearest = n.global_position
		objectives[0]["text"] = "Mühimmat depoları (%d/3)" % dead
		nav_point = nearest
		nav_label = "DEPO"
		if dead >= 3:
			objectives[0]["done"] = true
			_message("Depolar yok edildi — üsse dön!", 4.0)
		return
	nav_point = world_point(0, 600, 300.0)
	nav_label = "ANA ÜS"
	if _near_base(v, 3000.0):
		objectives[1]["done"] = true
		_finish(true, "Derin saldırı tamamlandı")


## Deniz devriyesi: akıncılar kıyıya (RAID_GOAL, 3 km) varmadan batmalı.
func _check_raid(v: Vessel) -> void:
	var goal := world_point(NavalGroup.RAID_GOAL.x, NavalGroup.RAID_GOAL.y, 0.0)
	for sh in Warship.ships:
		if is_instance_valid(sh) and not sh.destroyed and sh.objective and sh.global_position.distance_to(goal) < 3000.0:
			_finish(false, "Akıncılar kıyıya ulaştı")
			return
	_check_units(v, "Akıncı korvetler", "AKINCI", func(n: Node) -> bool: return n is Warship)


## Havaalanı baskını: pistin en az iki bölümü + beş uçak / hangar.
func _check_airbase(_v: Vessel) -> void:
	if not is_instance_valid(_airbase):
		return
	var cut := 0
	for s in _airbase.runway:
		if s.destroyed:
			cut += 1
	var planes := 0
	for u in _airbase.units:
		if u.destroyed and (u in _airbase.parked or u.unit_name == "Uçak hangarı"):
			planes += 1
	objectives[0]["text"] = "Pisti kes (%d/2 bölüm)" % mini(cut, 2)
	objectives[1]["text"] = "Uçak ve hangar (%d/5)" % mini(planes, 5)
	objectives[0]["done"] = cut >= 2
	objectives[1]["done"] = planes >= 5
	nav_point = _airbase.runway[0].global_position if not objectives[0]["done"] else _airbase.parked[0].global_position
	nav_label = "PİST" if not objectives[0]["done"] else "APRON"
	if objectives[0]["done"] and objectives[1]["done"]:
		objectives[2]["done"] = true
		_finish(true, "Düşman üssü devre dışı")


## Uzaktan vuruş: sığınak; uzun menzilli SAM'a 25 km'den fazla yaklaşma uyarısı.
func _check_standoff(v: Vessel) -> void:
	for n in main.world.get_children():
		if n is GroundTarget and n.unit_name == "Komuta sığınağı":
			nav_point = n.global_position
			nav_label = "SIĞINAK"
			var d: float = n.global_position.distance_to(v.com_global())
			objectives[1]["done"] = d > 40000.0
			if n.destroyed:
				objectives[0]["done"] = true
				_finish(true, "Sığınak uzaktan vuruldu")
			return


func _enemy_dead(e: Vessel) -> bool:
	return not is_instance_valid(e) or e.parts.is_empty() or e.cockpit() == null or not e.has_pilot()


func _count_kills() -> void:
	var n := 0
	for e in _enemies:
		if _enemy_dead(e):
			n += 1
	if n > kills:
		# kanat adamının düşürdükleri hedefe sayılır ama oyuncuya yazılmaz
		var wing := WingFlight.take_kills(n - kills)
		for i in n - kills - wing:
			Crew.add_kill()
		if main.radio and n - kills > wing:
			main.radio.on_kill()
		_message("DÜŞMAN DÜŞÜRÜLDÜ!  +40 XP" if n - kills > wing else "KANAT 2 DÜŞÜRDÜ!", 2.5)
		Sfx.play_ui("lock_tone.ogg", -6.0, 1.3)
	kills = n


func _nearest_alive() -> Vessel:
	var best: Vessel = null
	var bd := INF
	var v: Vessel = main.vessel
	for e in _enemies:
		if not _enemy_dead(e):
			var d := e.com_global().distance_to(v.com_global())
			if d < bd:
				bd = d
				best = e
	return best


func _check_training(v: Vessel) -> void:
	if not objectives[0]["done"]:
		nav_point = null
		if v.radar_altitude() > 30.0 and v.airspeed() > 60.0:
			objectives[0]["done"] = true
			_message("Kalkış tamam — birinci halkaya git", 3.0)
		return
	if _ring_index < _rings.size():
		var ring := _rings[_ring_index]
		nav_point = ring.global_position
		nav_label = "HALKA %d" % (_ring_index + 1)
		for i in _rings.size():
			(_rings[i].material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.5) if i == _ring_index else (Color(1.0, 0.8, 0.2, 1.0) if i > _ring_index else Color(0.4, 0.4, 0.4))
		if v.com_global().distance_to(ring.global_position) < RING_RADIUS + 6.0:
			ring.visible = false
			_ring_index += 1
			objectives[1]["text"] = "Halkalardan geç (%d/%d)" % [_ring_index, _rings.size()]
			objectives[1]["done"] = _ring_index >= _rings.size()
			Sfx.play_ui("switch_4.ogg", 0.0, 1.5)
			_message("Halka %d ✓" % _ring_index, 2.0)
		return
	nav_point = world_point(0, 600, MissionManager.ground_height(0, 600) + 2.0)
	nav_label = "PİST"
	if v.ground_speed() < 2.0 and v.radar_altitude() < 4.0 and _near_base(v, 2200.0):
		objectives[2]["done"] = true
		_finish(true, "")


func _near_base(v: Vessel, r: float) -> bool:
	var base := world_point(0, 600, 12.0)
	var d := v.com_global() - base
	var up := Planet.up_at(base)
	return (d - up * d.dot(up)).length() < r


func _check_recon(v: Vessel) -> void:
	for i in _points.size():
		if objectives[i]["done"]:
			continue
		var p := _points[i]
		var g := ground_height(p.x, p.z)
		nav_point = world_point(p.x, p.z, g + 300.0)
		nav_label = "KEŞİF %s  (<600 m AGL)" % ["A", "B", "C"][i]
		var d := v.com_global() - (nav_point as Vector3)
		var up := Planet.up_at(nav_point)
		if (d - up * d.dot(up)).length() < 400.0 and v.radar_altitude() < 600.0:
			objectives[i]["done"] = true
			Sfx.play_ui("switch_4.ogg", 0.0, 1.8)
			_message("Fotoğraf çekildi ✓", 2.0)
		return
	nav_point = world_point(0, 600, 300.0)
	nav_label = "ÜS"
	if _near_base(v, 3000.0):
		objectives[3]["done"] = true
		_finish(true, "")


func _check_ground(v: Vessel) -> void:
	var total := 0
	var dead := 0
	var nearest: Vector3
	var nd := INF
	for n in main.world.get_children():
		if n is GroundTarget and n.objective:
			total += 1
			if n.destroyed:
				dead += 1
			else:
				var d: float = n.global_position.distance_to(v.com_global())
				if d < nd:
					nd = d
					nearest = n.global_position
	objectives[0]["text"] = "Konvoyu yok et (%d/%d)" % [dead, total]
	nav_point = nearest if nd < INF else null
	nav_label = "KONVOY"
	if total > 0 and dead >= total:
		objectives[0]["done"] = true
		objectives[1]["done"] = true
		_finish(true, "")
	# ilk araç vurulunca devriye saldırıya geçer
	if dead > 0 and not _enemies.is_empty() and is_instance_valid(_enemies[0]):
		for c in _enemies[0].get_children():
			if c is AIPilot and not c.aggressive:
				c.aggressive = true
				_message("Düşman devriye seni fark etti!", 3.0)


func _check_intercept(v: Vessel) -> void:
	for i in 2:
		var e := _enemies[i]
		if _enemy_dead(e):
			objectives[i]["done"] = true
		elif _near_base(e, 3000.0):
			_finish(false, "Bombardıman üsse ulaştı")
			return
	var t := _nearest_alive()
	nav_point = t.com_global() if t else null
	nav_label = t.craft_name if t else ""
	if objectives[0]["done"] and objectives[1]["done"]:
		objectives[2]["done"] = true
		_finish(true, "")


func _check_dogfight(_v: Vessel) -> void:
	var t := _nearest_alive()
	nav_point = t.com_global() if t else null
	nav_label = t.craft_name if t else ""
	if t == null:
		objectives[0]["done"] = true
		objectives[1]["done"] = true
		_finish(true, "")


func _check_superiority(_v: Vessel) -> void:
	var t := _nearest_alive()
	nav_point = t.com_global() if t else null
	nav_label = t.craft_name if t else ""
	if _wave == 1:
		objectives[0]["text"] = "1. dalga (%d/1)" % kills
		if kills >= 1:
			objectives[0]["done"] = true
			_spawn_wave()
	else:
		objectives[1]["text"] = "2. dalga (%d/2)" % (kills - 1)
		if kills >= 3:
			objectives[1]["done"] = true
			objectives[2]["done"] = true
			_finish(true, "")


# ------------------------------------------------------------------ bitiş

func _finish(success: bool, reason: String) -> void:
	if state != "running":
		return
	state = "success" if success else "fail"
	Crew.award(int(def.get("level", 1)) * 60 + 20 if success else 10, "ucus")
	if is_instance_valid(main.vessel):
		Crew.note_mission(success, String(def.get("id", "")), main.vessel.global_position)
	# büyük hedef primi (uçak gemisi vb.): ödülün üstüne
	var bonus := int(def.get("bonus", 0)) if success and not Career.sandbox() and not Game.test_flight else 0
	Career.money += bonus
	Career.total_earned += bonus
	money_gain = Career.mission_finished(String(def["id"]), int(def.get("level", 1)), success) + bonus
	fail_reason = reason
	nav_point = null
	if is_instance_valid(tracker):
		var notes: Array = gen.notes.duplicate() if gen else []
		if reason != "":
			notes.append(reason)
		tracker.finalize(success, notes)
	Sfx.play_ui("lock_tone.ogg" if success else "caution_beep.ogg", -4.0, 1.0 if success else 0.7)
	print("GÖREV %s: %s  süre=%.0f sn  düşürülen=%d  %s" % [def["id"], "BAŞARILI" if success else "BAŞARISIZ", elapsed, kills, reason])
	if Game.args.has("missiontest") or Game.args.has("genflighttest"):
		if Game.args.has("genflighttest"):
			var lr := Game.last_result.duplicate()
			lr.erase("card")
			print("GENFLIGHT result ", lr)
		get_tree().quit()
		return
	# sonuç ekranı uçak yere inip durunca (pilot öldüyse hemen)
	var v: Vessel = main.vessel
	var pilot_lost: bool = not is_instance_valid(v) or v.cockpit() == null or (not v.has_pilot() and not is_instance_valid(main.pilot))
	if pilot_lost or _stopped_on_ground(v):
		_show_result(success)
		return
	_await_landing = true
	objectives.append(_obj("Üsse dön, in ve dur"))
	_message(("GÖREV BAŞARILI!  Üsse dön ve in — sonuç inince." if success else "GÖREV BAŞARISIZ (%s) — üsse dön ve in." % reason), 7.0)
	if main.radio:
		main.radio.say(("%s, görev tamam, üsse dönün." if success else "%s, görev iptal, üsse dönün.") % main.radio.callsign(), "%s, RTB." % main.radio.callsign())


func _show_result(success: bool) -> void:
	main.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_result = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.92)
	sb.border_color = Color(0.45, 1.0, 0.65) if success else Color(1.0, 0.4, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	_result.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_result.add_child(box)
	var title := Label.new()
	title.text = "GÖREV BAŞARILI" if success else "GÖREV BAŞARISIZ"
	title.add_theme_font_override("font", _bold)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65) if success else Color(1.0, 0.45, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var info := Label.new()
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	info.text = "%s\n%s\nSüre %d:%02d   ·   Düşürülen %d" % [def["title"], fail_reason if not success else "Tüm hedefler tamamlandı", m, s, kills]
	info.add_theme_font_override("font", _font)
	info.add_theme_font_size_override("font_size", 17)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var specs := [["Tekrar dene", _restart], ["Hangara dön", _to_hangar], ["Serbest uçuşa devam", _continue_free]]
	if is_instance_valid(main.vessel) and main.vessel.has_pilot() and main.vessel.radar_altitude() > 20.0:
		specs.insert(0, ["✈ Pilot indirsin", _pilot_lands])
	for spec in specs:
		var b := Button.new()
		b.text = "  %s  " % spec[0]
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
	_ui.add_child(_result)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH


## Görev bitti, uçak havada: pilot en yakın meydana kendisi iner (otomatik iniş),
## inince uçuş raporu açılır.
func _pilot_lands() -> void:
	if is_instance_valid(_result):
		_result.queue_free()
	main.player.enabled = true
	main.start_autoland()


func _restart() -> void:
	main.close_flight(false)
	FloatingOrigin.reset_world()
	FloatingOrigin.world_root = null
	Planet.reset()
	get_tree().reload_current_scene()


func _to_hangar() -> void:
	Game.mission = ""
	main.go_to_hangar()


func _continue_free() -> void:
	main.player.enabled = true
	Game.mission = ""
	if is_instance_valid(_result):
		_result.queue_free()
	def = {}
	objectives.clear()
	_ui.queue_redraw()


func _message(text: String, t: float) -> void:
	if main and main.hud:
		main.hud.show_message(text, t)


# ------------------------------------------------------------------ ekran

func _process(_delta: float) -> void:
	_ui.queue_redraw()


func _draw_ui() -> void:
	if def.is_empty():
		return
	var cam: Camera3D = main.camera
	# görev listesi (üstte, sol savaş panelinin sağında; paneller kapalıysa sol üstte)
	var x := 330.0 if Hud.panels_open else 18.0
	var y := 68.0
	var h := 30.0 + objectives.size() * 22.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.7)
	sb.border_color = Color(1.0, 0.8, 0.3, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(8)
	_ui.draw_style_box(sb, Rect2(x, y, 300, h))
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	var tl := ""
	if def.has("time"):
		var rem := maxf(def["time"] - elapsed, 0.0)
		tl = "   kalan %d:%02d" % [int(rem) / 60, int(rem) % 60]
	_text(Vector2(x + 12, y + 20), "%s   %d:%02d%s" % [String(def["title"]).to_upper(), m, s, tl], 13, Color(1.0, 0.82, 0.4), _bold)
	for i in objectives.size():
		var o := objectives[i]
		var col := Color(0.45, 1.0, 0.6) if o["done"] else Color(0.88, 0.9, 0.93)
		_text(Vector2(x + 14, y + 44 + i * 22), ("✓  " if o["done"] else "○  ") + String(o["text"]), 14, col, _font)
	# yön işareti
	if nav_point != null and is_instance_valid(cam) and state == "running":
		var p: Vector3 = nav_point
		var d := p.distance_to(cam.global_position)
		var label := "%s  %s" % [nav_label, ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % d)]
		var col := Color(1.0, 0.82, 0.3)
		var size := _ui.size
		if not cam.is_position_behind(p):
			var sp := cam.unproject_position(p)
			if Rect2(Vector2.ZERO, size).grow(-30).has_point(sp):
				var r := 11.0
				_ui.draw_polyline(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0), sp + Vector2(0, -r)]), col, 2.0, true)
				var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				_text(sp + Vector2(-w * 0.5, -18), label, 13, col, _bold)
				return
		var local := cam.global_basis.inverse() * (p - cam.global_position)
		var dir := Vector2(local.x, -local.y).normalized()
		var c := size * 0.5
		var pos := c + dir * (minf(c.x, c.y) - 90.0)
		var n := dir.orthogonal()
		_ui.draw_colored_polygon(PackedVector2Array([pos + dir * 18, pos + n * 10, pos - n * 10]), col)
		var w2 := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text(pos - dir * 26 + Vector2(-w2 * 0.5, 5), label, 13, col, _bold)


func _text(pos: Vector2, text: String, sz: int, col: Color, font: Font) -> void:
	_ui.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6))
	_ui.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


# ------------------------------------------------------------------ sivil görevler

## Üssten r1..r2 uzaklıkta, düz ve kara üstünde bir nokta (aynı tohumla hep aynı yer).
static func _find_flat(r1: float, r2: float, seed_v: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var best := Vector3(0, ground_height(0, -r1), -r1)
	var best_score := INF
	for i in 400:
		var a := rng.randf() * TAU
		var r := rng.randf_range(r1, r2)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := ground_height(x, z)
		if h < 6.0:
			continue
		var diff := 0.0
		for o in [Vector2(180, 0), Vector2(-180, 0), Vector2(0, 180), Vector2(0, -180), Vector2(130, 130), Vector2(-130, -130)]:
			diff = maxf(diff, absf(ground_height(x + o.x, z + o.y) - h))
		if diff < best_score:
			best_score = diff
			best = Vector3(x, h, z)
		if diff < 3.0:
			break
	return best


## Bölgeyi işaretle: duman sütunu, işaret ışığı; kurtarmada kazazede figürleri,
## kargoda turuncu bırakma halkası.
func _mark_site(s: Vector3, people: bool) -> void:
	var pos := world_point(s.x, s.z, s.y)
	var root := Node3D.new()
	main.world.add_child(root)
	root.global_position = pos
	root.global_basis = Planet.local_basis(pos)
	var smoke := Effects.smoke_column()
	root.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.omni_range = 60.0
	light.light_energy = 4.0
	light.position = Vector3(0, 3, 0)
	root.add_child(light)
	if people:
		for i in 3:
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.28
			cap.height = 1.75
			body.mesh = cap
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.45, 0.1)
			body.material_override = m
			body.position = Vector3(-3 + i * 2.2, 0.88, 8)
			root.add_child(body)
	else:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 146.0
		t.outer_radius = 152.0
		t.rings = 96
		ring.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.5, 0.1)
		ring.material_override = m
		ring.position = Vector3(0, 2.0, 0)
		root.add_child(ring)
	_site_node = root


var _site_node: Node3D


func _horiz_dist(v: Vessel, world: Vector3) -> float:
	var d := v.com_global() - world
	var up := Planet.up_at(world)
	return (d - up * d.dot(up)).length()


func _grounded(v: Vessel) -> bool:
	for m in v.modules:
		if m is LandingGearModule and m.grounded:
			return true
	return false


func _check_rescue(v: Vessel, delta: float) -> void:
	var site_w := world_point(_site.x, _site.z, _site.y)
	match _phase:
		0:
			nav_point = site_w
			nav_label = "KAZAZEDELER"
			if _grounded(v) and v.ground_speed() < 2.0 and _horiz_dist(v, site_w) < 250.0:
				objectives[0]["done"] = true
				_wait += delta
				objectives[1]["text"] = "Kazazedeler biniyor… %d sn" % ceili(5.0 - _wait)
				if _wait >= 5.0:
					v.board_passengers(3)
					objectives[1]["text"] = "Kazazedeleri al (3/3)"
					objectives[1]["done"] = true
					if is_instance_valid(_site_node):
						for c in _site_node.get_children():
							if c is MeshInstance3D and c.mesh is CapsuleMesh:
								c.visible = false
					_message("Kazazedeler alındı — üsse dön!", 4.0)
					_phase = 1
			else:
				_wait = 0.0
		1:
			nav_point = world_point(0, 600, 300.0)
			nav_label = "ÜS"
			if _grounded(v) and v.ground_speed() < 2.0 and _near_base(v, 2500.0):
				objectives[2]["done"] = true
				_finish(true, "")


func _check_passengers(v: Vessel, delta: float) -> void:
	var grounded := _grounded(v)
	# konfor: yatış, G ve sert iniş
	if not grounded:
		_airborne_t += delta
		_last_vs = v.vertical_speed()
		var roll := absf(v.roll_deg())
		if roll > 35.0:
			_comfort -= (roll - 35.0) * 0.12 * delta
		var g := v.g_force
		if g > 1.8:
			_comfort -= (g - 1.8) * 9.0 * delta
		elif g < 0.4:
			_comfort -= (0.4 - g) * 12.0 * delta
	elif _airborne_t > 10.0:
		_airborne_t = 0.0
		if _last_vs < -3.0:
			_comfort -= 25.0
			_message("Sert iniş! Yolcular hiç memnun değil", 3.0)
	_comfort = clampf(_comfort, 0.0, 100.0)
	objectives[3]["text"] = "Konfor %%%d" % _comfort
	objectives[3]["done"] = _comfort >= 40.0
	if _comfort < 40.0:
		_finish(false, "Yolcular çok rahatsız oldu (konfor %%%d)" % _comfort)
		return
	for i in _points.size():
		if objectives[i]["done"]:
			continue
		var p := _points[i]
		nav_point = world_point(p.x, p.z, p.y)
		nav_label = ["SAHİL", "TEPELER"][i]
		if _horiz_dist(v, nav_point) < 1000.0:
			objectives[i]["done"] = true
			_message("Yolcular manzaraya hayran! ✓", 2.5)
		return
	nav_point = world_point(0, 600, 300.0)
	nav_label = "ÜS"
	if grounded and v.ground_speed() < 2.0 and _near_base(v, 2500.0):
		objectives[2]["done"] = true
		_finish(true, "")


func _check_cargo(v: Vessel) -> void:
	var site_w := world_point(_site.x, _site.z, _site.y)
	nav_point = site_w
	nav_label = "BIRAKMA BÖLGESİ"
	var flying := 0
	for n in main.world.get_children():
		if n is CargoCrate:
			if not n.down:
				flying += 1
			elif not n.counted:
				n.counted = true
				var d: Vector3 = n.global_position - site_w
				var up := Planet.up_at(site_w)
				var hd: float = (d - up * d.dot(up)).length()
				if hd < 150.0:
					_inside += 1
					_message("Sandık bölgede! (%d m)" % hd, 2.5)
				else:
					_message("Sandık bölge dışına düştü (%d m)" % hd, 2.5)
	objectives[0]["text"] = "Sandıklar bölgede (%d/3)" % _inside
	if _inside >= 3:
		objectives[0]["done"] = true
		_finish(true, "")
	elif v.cargo_left() == 0 and flying == 0 and _inside < 3:
		_finish(false, "Sandıklar bitti, bölgeye yalnızca %d tanesi indi" % _inside)


## Yolcu konforu: yatış, G ve sert iniş puan düşürür. idx: konfor hedefinin sırası.
## Konfor %40 altına düşerse true (görev başarısız).
func _update_comfort(v: Vessel, delta: float, idx: int) -> bool:
	if not _grounded(v):
		_airborne_t += delta
		_last_vs = v.vertical_speed()
		var roll := absf(v.roll_deg())
		if roll > 35.0:
			_comfort -= (roll - 35.0) * 0.12 * delta
		var g := v.g_force
		if g > 1.8:
			_comfort -= (g - 1.8) * 9.0 * delta
		elif g < 0.4:
			_comfort -= (0.4 - g) * 12.0 * delta
	elif _airborne_t > 10.0:
		_airborne_t = 0.0
		if _last_vs < -3.0:
			_comfort -= 25.0
			_message("Sert iniş! Yolcular hiç memnun değil", 3.0)
	_comfort = clampf(_comfort, 0.0, 100.0)
	objectives[idx]["text"] = "Konfor %%%d" % _comfort
	objectives[idx]["done"] = _comfort >= 40.0
	if _comfort < 40.0:
		_finish(false, "Yolcular çok rahatsız oldu (konfor %%%d)" % _comfort)
		return true
	return false


func _check_transfer(v: Vessel, delta: float) -> void:
	if _update_comfort(v, delta, 2):
		return
	if not objectives[0]["done"]:
		var town := Towns.town_point("Ovaköy")
		nav_point = world_point(town.x, town.y, ground_height(town.x, town.y) + 600.0)
		nav_label = "OVAKÖY"
		if _horiz_dist(v, nav_point) < 1500.0:
			objectives[0]["done"] = true
			_message("Ovaköy üzerinden geçildi — Kuzey Havaalanı'na devam", 3.0)
		return
	var af: Dictionary = TerrainGen.AIRFIELDS[1]
	var xz: Vector2 = af["xz"]
	nav_point = world_point(xz.x, xz.y, float(af["elev"]) + 2.0)
	nav_label = "KUZEY HAVAALANI"
	if _grounded(v) and v.ground_speed() < 2.0 and _horiz_dist(v, nav_point) < 1500.0:
		objectives[1]["done"] = true
		_finish(true, "")


var _freight_total := 0
var _unload_t := 0.0


## Ağır nakliye: Kuzey Havaalanı'na in ve dur; yer ekibi sandıkları tek tek indirir (uçak
## durdukça her 1.2 sn bir sandık). Hepsi inince görev biter. Uçak kalkarsa boşaltma bekler.
func _check_freight(v: Vessel, delta: float) -> void:
	var af: Dictionary = TerrainGen.AIRFIELDS[1]
	var xz: Vector2 = af["xz"]
	nav_point = world_point(xz.x, xz.y, float(af["elev"]) + 2.0)
	nav_label = "KUZEY HAVAALANI"
	var parked := _grounded(v) and v.ground_speed() < 2.0 and _horiz_dist(v, nav_point) < 1500.0
	if parked and not objectives[0]["done"]:
		objectives[0]["done"] = true
		_message("Yer ekibi geliyor — yük boşaltılıyor, uçağı oynatma", 3.0)
	if not objectives[0]["done"] or not parked:
		return
	_unload_t += delta
	if _unload_t < 1.2:
		return
	_unload_t = 0.0
	for m in v.modules:
		if m is CargoModule and m.crates > 0:
			m.crates -= 1
			Sfx.play_at("hydraulic_thunk.ogg", m.part.global_position, -6.0, randf_range(0.9, 1.1), 200.0)
			break
	var done := _freight_total - v.cargo_left()
	objectives[1]["text"] = "Yükü boşalt (%d/%d)" % [done, _freight_total]
	if v.cargo_left() <= 0:
		objectives[1]["done"] = true
		_finish(true, "")


## Brifing için görev noktaları ve hedef özeti (harita: [ad, yüzey xz, renk]).
static func briefing(id: String) -> Dictionary:
	if id == "gen":
		return GenMission.briefing_info(GenMission.card_now())
	var red := Color(1.0, 0.35, 0.3)
	var gold := Color(1.0, 0.82, 0.3)
	var green := Color(0.45, 1.0, 0.6)
	var pts := []
	var obj := []
	match id:
		"egitim":
			var rings := [Vector2(-1500, -4500), Vector2(2500, -7500), Vector2(5500, -3500), Vector2(2500, 3500)]
			for i in rings.size():
				pts.append(["H%d" % (i + 1), rings[i], gold])
			obj = ["Kalkış yap", "Dört halkadan sırayla geç", "Piste in ve dur"]
		"kesif":
			pts = [["A", Vector2(-6000, -9000), gold], ["B", Vector2(4000, -16000), gold], ["C", Vector2(9000, -5000), gold]]
			obj = ["A, B, C noktalarının üzerinden 600 m AGL altında geç", "Üsse dön"]
		"kara":
			pts = [["Konvoy", Vector2(-1300, -2500), red], ["Uçaksavar", Vector2(-1000, -2900), red], ["Devriye", Vector2(-1500, -3500), red]]
			obj = ["Yolda ilerleyen 6 araçlık konvoyu yok et", "Uçaksavar toplarına (3 km) ve devriye avcıya dikkat"]
		"heli":
			pts = [["Helikopterler", Vector2(6600, -21500), red], ["Dereköy", Towns.town_point("Dereköy"), gold], ["Sen", Vector2(0, -6000), green]]
			obj = ["İki saldırı helikopterini düşür", "Yaklaşınca topla ateş ederler"]
		"sam":
			pts = [["SAM 1", SAM_SITES[0], red], ["SAM 2", SAM_SITES[1], red], ["Sen", Vector2(0, -4000), green]]
			obj = ["İki SAM rampasını yok et", "9 km içinde 120 m üstünde görünme — alçak uç ya da rampaya dik dön"]
		"onleme":
			pts = [["Bombardıman 1", Vector2(-800, -26000), red], ["Bombardıman 2", Vector2(800, -27500), red]]
			obj = ["İki bombardımanı üsse 3 km yaklaşmadan düşür", "Süre 5 dakika"]
		"it":
			pts = [["As pilot", Vector2(0, -6000), red], ["Sen", Vector2(0, 0), green]]
			obj = ["Düşman asını düşür", "Hayatta kal"]
		"ustunluk":
			pts = [["1. dalga", Vector2(0, -9000), red], ["2. dalga", Vector2(-2000, -11000), red], ["", Vector2(2500, -12000), red], ["Sen", Vector2(0, 2000), green]]
			obj = ["İlk dalgayı (1) düşür", "İkinci dalgayı (2) düşür", "Hayatta kal"]
		"yolcu":
			pts = [["Sahil", Vector2(7000, -4000), gold], ["Tepeler", Vector2(-5000, -11000), gold]]
			obj = ["İki seyir noktasının 1 km yakınından geç", "Üsse in ve dur", "Konforu %40 üstünde tut"]
		"kurtarma":
			var s := _find_flat(7000.0, 12000.0, 11)
			pts = [["Kazazedeler", Vector2(s.x, s.z), red]]
			obj = ["Kazazedelerin yanına (250 m) in ve dur", "Binmelerini bekle (5 sn)", "Üsse getir"]
		"kargo":
			var s := _find_flat(7000.0, 12000.0, 23)
			pts = [["Bırakma bölgesi", Vector2(s.x, s.z), red]]
			obj = ["En az 3 sandığı 150 m bölgeye bırak"]
		"nakliye":
			pts = [["Ana Üs (yük)", Vector2(0, 0), gold], ["Kuzey Havaalanı (teslim)", TerrainGen.AIRFIELDS[1]["xz"], green]]
			obj = ["En az 8 sandık kargoyla kalk", "Kuzey Havaalanı'na in ve dur", "Yer ekibi boşaltırken bekle"]
		"tasima":
			pts = [["Ovaköy", Towns.town_point("Ovaköy"), gold], ["Varış", TerrainGen.AIRFIELDS[1]["xz"], green]]
			obj = ["Ovaköy üzerinden geç", "Kuzey Havaalanı'na in ve dur", "Konforu %40 üstünde tut"]
		"sead":
			pts = [["Uzun menzilli SAM (40 km)", LR_SAM, red], ["SAM", Vector2(-3000, -20000), red], ["SAM", Vector2(-9500, -21000), red],
				["Erken uyarı", EW_SITE, gold], ["Sen", Vector2(0, 16000), green]]
			obj = ["Uzun menzilli bataryayı (fırlatıcı, arama + takip radarı), iki SAM'ı ve radarı yok et", "Radar avcısı füze yayına kilitlenir", "Alçak uç, chaff (Ş), ECM"]
		"derin":
			pts = [["Depolar", DEPOTS[0], red], ["Erken uyarı radarı", Vector2(-3000, -15000), gold], ["Düşman üssü", Vector2(-21500, -24000), red], ["Sen", Vector2(0, 2000), green]]
			obj = ["Üç mühimmat deposunu yok et", "Erken uyarı radarına görünme (Shift+U: arazi takibi)", "Üsse dön"]
		"ussaldiri":
			pts = [["Düşman havaalanı", Vector2(-12000, -24500), red], ["Sen", Vector2(0, -2000), green]]
			obj = ["Pistin en az iki bölümünü kes", "Park etmiş uçak ve hangarlardan beşini yok et", "Alarmda avcılar kalkar — önce pist"]
		"uzak":
			pts = [["Sığınak", BUNKER, red], ["SAM 40 km", BUNKER + Vector2(1800, 1500), red], ["Sen", Vector2(0, 15000), green]]
			obj = ["Komuta sığınağını seyir füzesi / süzülen bombayla vur", "Haritada (M) sol tık: GPS hedefi", "SAM menziline (40 km) girme"]
		"deniz":
			var sp := _sea_points(2)
			pts = [["Korvet 1", sp[0], red], ["Korvet 2", sp[1], red], ["Sen", Vector2(0, 2000), green]]
			obj = ["İki korveti batır", "Gemi SAM'ı 12 km, radarı 30 km", "Gemi savar füze: 15 m'de, son evrede kendi radarı"]
		"filo":
			pts = [["Uçak gemisi", NavalGroup.FLEET_XZ, red], ["Rota", NavalGroup.FLEET_ROUTE[2], gold], ["Sen", Vector2(0, 2000), green]]
			obj = ["Uçak gemisini batır (+15.000 ₺ prim)", "28 km içinde görülürsen avcı kaldırır", "Muhrip topu 6.5 km, SAM 16 km"]
		"firkateyn":
			pts = [["Fırkateynler", NavalGroup.HUNT_XZ, red], ["Rota", NavalGroup.HUNT_ROUTE[1], gold], ["Sen", Vector2(0, -2000), green]]
			obj = ["İki fırkateyni batır", "Baş topu 6.5 km, SAM 16 km, radar 40 km", "Gemi savar füzeyi menzil dışından at"]
		"devriye":
			pts = [["Akıncılar", NavalGroup.RAID_XZ, red], ["Kıyı", NavalGroup.RAID_GOAL, gold], ["Sen", Vector2(0, 2000), green]]
			obj = ["Üç akıncı korveti batır", "Kıyıya (3 km) ulaşmalarına izin verme"]
		"sondarbe":
			pts = [["Kara Doğan", Ace.FINALE_XZ, red], ["Düşman karargâhı", Vector2(-28000, -11000), gold], ["Sen", Vector2(0, -2000), green]]
			obj = ["Kara Doğan'ı düşür (KD-01, siyah-kırmızı)", "Eskortlar isteğe bağlı", Ace.intel_text()]
	return {"points": pts, "objectives": obj}


# ------------------------------------------------------------------ yer birimleri

## Serbest uçuştaki sabit talim tanklarını kaldır (görev kendi birimlerini koyar).
func _clear_static_targets() -> void:
	for n in main.world.get_children():
		if n.get_script() == GroundTarget:
			n.queue_free()


## Birimi (doğu, güney) noktasına araziye oturtarak ekle. Konvoy aracı kendini yerleştirir.
func _add_unit(u: GroundTarget, xz := Vector2.ZERO, agl := 0.0) -> void:
	main.world.add_child(u)
	if u is ConvoyTruck:
		return
	var h := MissionManager.ground_height(xz.x, xz.y)
	var pos := MissionManager.world_point(xz.x, xz.y, maxf(h, 0.5) + agl)
	u.global_transform = Transform3D(Planet.local_basis(pos).rotated(Planet.up_at(pos), randf() * TAU), pos)


## Yol boyunca `dist` metredeki nokta.
static func _road_point(road: Array[Vector2], dist: float) -> Vector2:
	for i in road.size() - 1:
		var l := road[i].distance_to(road[i + 1])
		if dist <= l:
			return road[i].lerp(road[i + 1], dist / l)
		dist -= l
	return road[road.size() - 1]


## Genel "şu birimleri yok et" kontrolü.
func _check_units(v: Vessel, label: String, nav: String, filter: Callable) -> void:
	var total := 0
	var dead := 0
	var nearest: Variant = null
	var nd := INF
	for n in main.world.get_children():
		if n is GroundTarget and n.objective and filter.call(n):
			total += 1
			if n.destroyed:
				dead += 1
			else:
				var d: float = n.global_position.distance_to(v.com_global())
				if d < nd:
					nd = d
					nearest = n.global_position
	objectives[0]["text"] = "%s (%d/%d)" % [label, dead, total]
	nav_point = nearest
	nav_label = nav
	if total > 0 and dead >= total:
		objectives[0]["done"] = true
		objectives[1]["done"] = true
		_finish(true, "")


# ------------------------------------------------------------------ görev sonrası dönüş

func _stopped_on_ground(v: Vessel) -> bool:
	return is_instance_valid(v) and _grounded(v) and v.ground_speed() < 2.0


## Görev bitti, uçak havada: en yakın meydana yön göster, inip durunca sonuç ekranını aç.
func _wait_landing() -> void:
	var v: Vessel = main.vessel
	if main._ejected:
		_await_landing = false      # fırlatma: sonuç, pilot inince uçuş raporunda
		return
	if not is_instance_valid(v) or v.cockpit() == null or not v.has_pilot():
		if not is_instance_valid(main.pilot):
			_await_landing = false
			_show_result(state == "success")
		return
	var best := INF
	for a: Dictionary in TerrainGen.AIRFIELDS:
		var xz: Vector2 = a["xz"]
		var p := MissionManager.world_point(xz.x, xz.y, float(a["elev"]))
		var d := p.distance_to(v.com_global())
		if d < best:
			best = d
			nav_point = p
			nav_label = String(a["name"]).to_upper()
	if _stopped_on_ground(v):
		_await_landing = false
		objectives[objectives.size() - 1]["done"] = true
		_show_result(state == "success")
