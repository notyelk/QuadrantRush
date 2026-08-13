extends Control

## A pauta do dia, mostrada ANTES do expediente começar — Etapa 6 (interface).
##
## Fica ENTRE a tela de título e a fase, e não dentro dela: dentro, teria de pausar a
## árvore no _ready, e as suítes de teste esbarrariam num painel modal.
##
## Não some sozinho. Quem fecha é o jogador.

signal fechado

## Os comandos e as regras de cada dia. O Dia 3 tem outro verbo — lá não se encosta em
## nada, carrega-se um papel por vez até o canto certo — e anunciar as regras do corredor
## naquela arena ensinaria o controle errado.
const PAUTA := {
	1: {
		"regras": [
			["ENCOSTAR  =  faço agora", "8fd6a8"],
			["PASSAR DIRETO  =  deixo para lá", "f2c14e"],
			["SUBIR NA BANDEJA DO COLEGA  =  delego", "5aa9e6"],
			["SEGURAR SHIFT  =  me concentro (leio de longe, mas ando devagar)", "74a4f1"],
		],
		"alerta": "O elevador só abre com todas as urgentes resolvidas.",
	},
	2: {
		"regras": [
			["ENCOSTAR  =  faço agora", "8fd6a8"],
			["PASSAR DIRETO  =  deixo para lá", "f2c14e"],
			["SUBIR NA BANDEJA DO COLEGA  =  delego", "5aa9e6"],
			["SEGURAR SHIFT  =  me concentro (leio de longe, mas ando devagar)", "74a4f1"],
		],
		"alerta": "As tarefas chegam sozinhas, e o que você adiar volta como urgência.",
	},
	3: {
		"regras": [
			["ENCOSTAR NUM PAPEL  =  pego (um por vez)", "8fd6a8"],
			["POUSAR NUM CANTO  =  classifico naquele quadrante", "5aa9e6"],
			["S ou SETA PARA BAIXO  =  largo o papel", "f2c14e"],
			["SEGURAR SHIFT  =  me concentro (leio de longe, mas ando devagar)", "74a4f1"],
		],
		"alerta": "Sobreviva ao expediente. Quem derruba você é a pilha de pendências.",
	},
}

@onready var titulo: Label = $Painel/Conteudo/Titulo
@onready var resumo: Label = $Painel/Conteudo/Resumo
@onready var instrucao: Label = $Painel/Conteudo/Instrucao
@onready var regras: VBoxContainer = $Painel/Conteudo/Regras
@onready var alerta: Label = $Painel/Conteudo/Alerta
@onready var continuar: Label = $Painel/Conteudo/Continuar

var _pronto := false


func _ready() -> void:
	# Um instante antes de aceitar tecla: sem isso, o mesmo Enter que apertou "Bater o
	# ponto" na tela de título fecharia o briefing no mesmo quadro em que ele aparece.
	await get_tree().create_timer(0.35).timeout
	_pronto = true
	continuar.visible = true


func montar(dia: int, nome_do_dia: String, total_de_tarefas: int, segundos: int) -> void:
	titulo.text = nome_do_dia.to_upper()
	resumo.text = "%d tarefas na sua mesa. %d segundos de expediente.\nNão vai dar para todas." % [
		total_de_tarefas, segundos,
	]

	var pauta: Dictionary = PAUTA.get(dia, PAUTA[1])
	instrucao.text = (
		"Cada papel é uma tarefa. Chegue perto para ler o que é, e responda com o corpo:"
	)
	alerta.text = str(pauta["alerta"])

	for filho in regras.get_children():
		regras.remove_child(filho)
		filho.queue_free()
	for regra in pauta["regras"]:
		var linha := Label.new()
		linha.text = str(regra[0])
		linha.add_theme_font_size_override("font_size", 7)
		linha.add_theme_color_override("font_color", Color(str(regra[1])))
		linha.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		linha.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		regras.add_child(linha)


func _unhandled_input(evento: InputEvent) -> void:
	if not _pronto:
		return
	# Tipo explícito: em modo estrito o GDScript não infere bool a partir de uma cadeia
	# de `is` com `and`/`or`.
	var confirmou: bool = (
		(evento is InputEventKey and evento.is_pressed())
		or (evento is InputEventMouseButton and evento.is_pressed())
	)
	if confirmou:
		get_viewport().set_input_as_handled()
		fechado.emit()
