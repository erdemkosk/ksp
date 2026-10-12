class_name EcmModule
extends PartModule
## Elektronik karıştırıcı (ECM) podu. Açıkken (güç varken ve pod sağlamken) düşman radarlarına
## gürültü basar:
##   • arama radarları ve SAM seni JAM_RANGE_FACTOR kadar daha kısa menzilde bulur
##   • radar füzesinin arayıcısı uzaktayken (> BURN_THROUGH) kilidi daha kolay kaybeder
## Bedeli: sürekli yayın yaparsın. Düşman RWR'ı seni çok uzaktan "J" olarak görür, düşman
## yapay zekâsı da yayını izleyerek seni daha uzaktan fark eder (home-on-jam).
## Eylem panelinden ya da parça penceresinden kapatılabilir.

const JAM_RANGE_FACTOR := 0.55
const BURN_THROUGH := 3500.0       ## bu mesafenin altında radar gürültüyü yener
const EMIT_RANGE := 40000.0        ## yayının fark edildiği mesafe

var enabled := true


func active() -> bool:
	return enabled and vessel.has_power() and part.health_ratio() > 0.3
