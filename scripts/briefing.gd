extends Control

## A pauta do dia, mostrada ANTES do expediente começar — Etapa 6 (interface).
##
## A faixa do HUD não serve para explicar a fase: ela sobe junto com o cronômetro e some
## em segundos. Como a mecânica central é LER a tarefa e decidir, isso precisa estar dito
## antes de o relógio começar.
##
## Fica ENTRE a tela de título e a fase, e não dentro dela. Isso é decisão de projeto,
## não acaso: se ele vivesse dentro da fase, teria de pausar a árvore no _ready, e as
## quatro suítes de teste (que instanciam a fase e dirigem o jogador quadro a quadro)
## passariam a esbarrar num painel modal. Aqui a fase continua exatamente como os testes
## a conhecem.
##
## Também não tem tempo para sumir sozinho. Quem fecha é o jogador.

signal fechado

@onready var titulo: Label = $Painel/Conteudo/Titulo
@onready var resumo: Label = $Painel/Conteudo/Resumo
@onready var regras: VBoxContainer = $Painel/Conteudo/Regras
@onready var continuar: Label = $Painel/Conteudo/Continuar

var _pronto := false


func _ready() -> void:
	# Um instante antes de aceitar tecla: sem isso, o mesmo Enter que apertou "Bater o
	# ponto" na tela de título fecharia o briefing no mesmo quadro em que ele aparece.
	await get_tree().create_timer(0.35).timeout
	_pronto = true
	continuar.visible = true


func montar(nome_do_dia: String, total_de_tarefas: int, segundos: int) -> void:
	titulo.text = nome_do_dia.to_upper()
	resumo.text = "%d tarefas na sua mesa. %d segundos de expediente.\nNão vai dar para todas." % [
		total_de_tarefas, segundos,
	]


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
