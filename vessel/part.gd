class_name Part
extends Node3D
## Aracın bir parçası. Davranışı alt düğümlerindeki PartModule'ler belirler.

var part_id := ""
var def := {}
var title := ""
var dry_mass := 0.0
var max_hp := 100.0
var hp := 100.0
## Atalet hesabı için yaklaşık kutu boyutu (yerel eksenlerde).
var size := Vector3.ONE
## Suya batma oranı (0..1), Hydro yazar
var submerged := 0.0
## Yapısal dayanım (N). Aşılırsa parça hasar alır, çok aşılırsa anında kopar.
var strength := 0.0
## Bu karede parçaya etkiyen dış kuvvetler (aerodinamik, itki) — modüller ekler
var aero_load := Vector3.ZERO
## Son yük oranı (yük / dayanım), göstergeler için
var stress := 0.0
var vessel: Vessel
var modules: Array[PartModule] = []
## Vessel'in çocuğu olan çarpışma şekilleri (RigidBody şekilleri doğrudan çocuk olmalı).
var colliders: Array[CollisionShape3D] = []
## Hasar kaplaması (is/yanık); vurgu kaplamaları kalkınca buna döner (DamageFx yazar).
var damage_overlay: Material


func add_module(module: PartModule) -> void:
	module.part = self
	modules.append(module)
	add_child(module)


func get_mass() -> float:
	var m := dry_mass
	for module in modules:
		m += module.extra_mass()
	return m


func health_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


## Parçanın araç uzayındaki kaba kutusu (komşuluk / kopma hesabı için).
func local_aabb(margin := 0.15) -> AABB:
	var ext := (basis * size).abs() * 0.5
	return AABB(position - ext, ext * 2.0).grow(margin)
