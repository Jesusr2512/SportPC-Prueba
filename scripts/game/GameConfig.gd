class_name GameConfig
extends Object

enum CombatStyle { CLASSIC, TWIN_BLADES }
enum ArenaStage { SUN_ISLAND, VOLCANIC_BRIDGE, SKY_SANCTUARY }

static var match_mode: String = "1p" # "1p" or "2p"
static var ai_difficulty: int = 1 # 0=Novato, 1=Pro, 2=Campeón, 3=Leyenda
static var combat_style: int = CombatStyle.CLASSIC
static var arena_stage: int = ArenaStage.SUN_ISLAND
static var dual_sense_sensitivity: float = 1.0 # Multiplier for swing velocity sensitivity


static func get_ai_name(level: int = -1) -> String:
	var lv := ai_difficulty if level < 0 else level
	match lv:
		0:
			return "Novato"
		2:
			return "Campeón"
		3:
			return "Leyenda"
		_:
			return "Pro"


static func get_stage_name(stage: int = -1) -> String:
	var s := arena_stage if stage < 0 else stage
	match s:
		ArenaStage.VOLCANIC_BRIDGE:
			return "Puente Volcánico"
		ArenaStage.SKY_SANCTUARY:
			return "Santuario Flotante"
		_:
			return "Isla del Sol"


static func get_style_name(style: int = -1) -> String:
	var st := combat_style if style < 0 else style
	match st:
		CombatStyle.TWIN_BLADES:
			return "Espadas Gemelas"
		_:
			return "Chambara Clásico"
