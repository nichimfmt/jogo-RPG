extends Node

# Caminho base dentro do projeto
var caminho_binario: String
var caminho_modelo: String = "res://models/llama-3.2-3b-instruct-q4_k_m.gguf"

func _ready() -> void:
	# Detecta o sistema operacional para escolher a pasta correta do executável
	if OS.get_name() == "Windows":
		caminho_binario = "res://llama_bin/win/llama-cli.exe"
	elif OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		caminho_binario = "res://llama_bin/linux/llama-cli"

func gerar_resposta_npc(prompt_jogador: String) -> String:
	var bin_abs = ProjectSettings.globalize_path(caminho_binario)
	var mod_abs = ProjectSettings.globalize_path(caminho_modelo)
	
	var args = PackedStringArray([
		"-m", mod_abs,
		"-p", prompt_jogador,
		"-n", "128",          # Limite de tokens
		"--temp", "0.7",      # Criatividade da resposta
		"--no-display-prompt"
	])
	
	var output = []
	var exit_code = OS.execute(bin_abs, args, output, true)
	
	if exit_code == 0 and output.size() > 0:
		return output[0].strip_edges()
	else:
		push_error("Erro ao chamar o llama-cli. Exit code: " + str(exit_code))
		return ""
