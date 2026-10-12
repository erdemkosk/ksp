class_name SplitterModule
extends PartModule
## Sınır tabaka ayırıcı: yanındaki hava alığının (AeroLinks bağlar) verimini artırır —
## gövde yüzeyindeki yavaş, türbülanslı hava alığa girmez. Etkisi IntakeModule.splitter_bonus.

const BONUS := 0.1           ## alık alanına +%10
const REACH := 1.8           ## alık merkezine en çok bu kadar uzakta olmalı (m)
