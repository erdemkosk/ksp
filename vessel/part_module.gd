class_name PartModule
extends Node
## Parça davranışlarının temel sınıfı (KSP'deki PartModule gibi).

var part: Part
var vessel: Vessel


## Parça tanımındaki parametrelerle kurulum.
func setup(_params: Dictionary) -> void:
	pass


## Vessel sahneye girip kütlesi hesaplandıktan sonra çağrılır.
func on_attached() -> void:
	pass


## Her fizik karesinde Vessel tarafından çağrılır.
func physics_tick(_delta: float) -> void:
	pass


## Parçanın kuru kütlesine eklenen kütle (ör. yakıt).
func extra_mass() -> float:
	return 0.0


## Parça isabet aldı (henüz kopmadı): kısmi arıza fırsatı (sıkışma, sızıntı…).
func on_damaged(_amount: float) -> void:
	pass
