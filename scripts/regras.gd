extends RefCounted
# ---------------------------------------------------------------
# REGRAS.GD - as regras de D&D feitas em CÓDIGO.
# A IA de texto NUNCA rola dados nem decide quem acertou: quem faz isso é este arquivo.
# Não precisa ser Autoload: o Tabuleiros.gd o carrega sozinho.
# ---------------------------------------------------------------


# Lê um texto de dado como "1d8+2" e devolve {"n": 1, "lados": 8, "mod": 2}
static func analisar(expressao: String) -> Dictionary:
	var texto: String = expressao.replace(" ", "").to_lower()
	var rx := RegEx.new()
	rx.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m: RegExMatch = rx.search(texto)
	if m == null:
		return {"n": 0, "lados": 0, "mod": texto.to_int()}
	var modificador: int = 0
	if m.get_string(3) != "":
		modificador = m.get_string(3).to_int()
	return {"n": m.get_string(1).to_int(), "lados": m.get_string(2).to_int(), "mod": modificador}


# Dano médio (para a IA tática "calcular" quanto vale um ataque)
static func media(expressao: String) -> float:
	var d: Dictionary = analisar(expressao)
	return float(d["n"]) * (float(d["lados"]) + 1.0) / 2.0 + float(d["mod"])


# Dano máximo possível
static func maximo(expressao: String) -> int:
	var d: Dictionary = analisar(expressao)
	return int(d["n"]) * int(d["lados"]) + int(d["mod"])


# Rola o dano. No acerto crítico os dados são rolados duas vezes.
static func rolar_dano(expressao: String, critico: bool = false, faces: Array[int] = []) -> int:
	var d: Dictionary = analisar(expressao)
	var total: int = int(d["mod"])
	var quantidade: int = int(d["n"])
	if critico:
		quantidade *= 2
	for i in range(quantidade):
		var face: int = randi_range(1, maxi(int(d["lados"]), 1))
		faces.append(face)
		total += face
	return maxi(total, 1)


# Chance de acertar (de 0.05 a 0.95). "Vantagem de altura" entra como bônus.
# Regra: d20 + bônus >= CA acerta; 20 natural sempre acerta; 1 natural sempre erra.
static func chance_de_acerto(bonus: int, ca: int) -> float:
	var chance: float = float(21 - (ca - bonus)) / 20.0
	return clampf(chance, 0.05, 0.95)


# Faz a rolagem de ataque completa.
static func rolar_ataque(bonus: int, ca: int) -> Dictionary:
	var d20: int = randi_range(1, 20)
	var total: int = d20 + bonus
	var critico: bool = d20 == 20
	var acertou: bool = critico or (d20 != 1 and total >= ca)
	return {"d20": d20, "total": total, "acertou": acertou, "critico": critico}
