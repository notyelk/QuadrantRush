extends CanvasLayer

## Encerramento do jogo, depois de vencer o último expediente.
##
## Três páginas: o que o jogador fez no dia final, o que cada quadrante da matriz pedia
## dele ao longo dos três dias, e o fecho. Não é uma tela de "você venceu" — é o momento
## em que o jogo diz em palavras a teoria que vinha dizendo em geometria.
##
## Roda com process_mode ALWAYS: entra por cima da tela de resultado, com a árvore pausada.

signal fechado

const Encaixe := preload("res://scripts/encaixe.gd")

@onready var painel: Control = $Painel
@onready var conteudo: VBoxContainer = $Painel/Conteudo
@onready var titulo: Label = $Painel/Conteudo/Titulo
@onready var subtitulo: Label = $Painel/Conteudo/Subtitulo
@onready var corpo: VBoxContainer = $Painel/Conteudo/Corpo
@onready var botao_continuar: Button = $Painel/Conteudo/Botoes/Continuar
@onready var botao_sair: Button = $Painel/Conteudo/Botoes/Sair

var _pagina := 0


func _ready() -> void:
	botao_continuar.pressed.connect(_ao_continuar)
	botao_sair.pressed.connect(_ao_sair)
	_montar()
	botao_continuar.grab_focus()


func _montar() -> void:
	for filho in corpo.get_children():
		corpo.remove_child(filho)
		filho.queue_free()

	match _pagina:
		0: _pagina_desempenho()
		1: _pagina_matriz()
		_: _pagina_fecho()

	botao_continuar.text = "Continuar" if _pagina < 2 else "Rever"
	_encaixar()


## O que aconteceu no expediente final. Os contadores do GameManager zeram a cada fase,
## então o que se pode afirmar aqui é o dia de encerramento — dizer "em três dias" seria
## somar números que ninguém guardou.
func _pagina_desempenho() -> void:
	var quem := Perfil.nickname if not Perfil.nickname.is_empty() else "Você"
	titulo.text = "TRÊS DIAS DE EXPEDIENTE"
	titulo.add_theme_color_override("font_color", Color("ffd166"))
	subtitulo.text = "%s atravessou a semana inteira. No dia de encerramento:" % quem

	var tratadas := 0
	for categoria in GameManager.Categoria.values():
		tratadas += int(GameManager.tarefas_por_categoria[categoria])

	_linha("Tarefas classificadas", "%d" % tratadas, Color("c3cad4"))
	for categoria in GameManager.Categoria.values():
		_linha(
			GameManager.NOME_CATEGORIA[categoria],
			"%d · %+d pts" % [
				int(GameManager.tarefas_por_categoria[categoria]),
				int(GameManager.pontuacao_por_categoria[categoria]),
			],
			GameManager.COR_CATEGORIA[categoria]
		)
	_linha(
		"Delegadas / resolvidas sozinho",
		"%d / %d" % [
			int(GameManager.acoes_por_tipo[GameManager.Acao.DELEGAR]),
			int(GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER]),
		],
		Color("5aa9e6")
	)
	_linha("Decisões fora do quadrante", "%d" % GameManager.equivocos.size(), Color("e05c5c"))
	_linha("Pontuação do dia", "%d pts" % GameManager.pontuacao_total, Color("ffd166"))


func _pagina_matriz() -> void:
	titulo.text = "O QUE VOCÊ ESTAVA FAZENDO"
	titulo.add_theme_color_override("font_color", Color("8fd6a8"))
	subtitulo.text = (
		"Cada dia cobrou um quadrante da Matriz de Eisenhower de um jeito diferente."
	)

	_paragrafo(
		GameManager.NOME_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE],
		"Prazo curto e consequência real. O elevador só abria com essas resolvidas: "
		+ "não havia como negociar com elas.",
		GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE]
	)
	_paragrafo(
		GameManager.NOME_CATEGORIA[GameManager.Categoria.IMPORTANTE_NAO_URGENTE],
		"Nunca estavam no seu caminho: exigiam um desvio deliberado. No Dia 2, as que "
		+ "você adiou voltaram como crise — é assim que se fabrica urgência.",
		GameManager.COR_CATEGORIA[GameManager.Categoria.IMPORTANTE_NAO_URGENTE]
	)
	_paragrafo(
		GameManager.NOME_CATEGORIA[GameManager.Categoria.URGENTE_NAO_IMPORTANTE],
		"Urgentes para os outros. Subir na bandeja custava habilidade; fazer sozinho "
		+ "custava o seu relógio.",
		GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_NAO_IMPORTANTE]
	)
	_paragrafo(
		GameManager.NOME_CATEGORIA[GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE],
		"O imposto de quem corre reto. Não se agendam para depois: descartam-se.",
		GameManager.COR_CATEGORIA[GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE]
	)


func _pagina_fecho() -> void:
	titulo.text = "FIM DO EXPEDIENTE"
	titulo.add_theme_color_override("font_color", Color("ffd166"))
	subtitulo.text = ""

	_paragrafo(
		"A MATRIZ NÃO É UMA LISTA",
		"Ela é uma decisão sobre o que NÃO vai ser feito. Por isso o jogo nunca deu "
		+ "tempo para tudo: sem escassez, priorizar não significa nada.",
		Color("c3cad4")
	)
	_paragrafo(
		"O SEGUNDO QUADRANTE É O QUE MUDA O DIA",
		"É o único que reduz o tamanho do primeiro. Todo dia em que ele fica para "
		+ "depois é um dia que empurra trabalho para o dia seguinte.",
		Color("4ea36b")
	)
	_paragrafo(
		"OBRIGADO POR BATER O PONTO",
		"Quadrant Rush é o produto prático de um Trabalho de Conclusão de Curso em "
		+ "Engenharia de Software.",
		Color("7d878f")
	)


func _linha(rotulo: String, valor: String, cor: Color) -> void:
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 6)

	var marca := ColorRect.new()
	marca.color = cor
	marca.custom_minimum_size = Vector2(3, 0)
	linha.add_child(marca)

	var nome := Label.new()
	nome.text = rotulo
	nome.add_theme_font_size_override("font_size", 7)
	nome.add_theme_color_override("font_color", cor)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(nome)

	var direita := Label.new()
	direita.text = valor
	direita.add_theme_font_size_override("font_size", 7)
	direita.add_theme_color_override("font_color", Color("c3cad4"))
	direita.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	direita.custom_minimum_size = Vector2(88, 0)
	linha.add_child(direita)

	corpo.add_child(linha)


func _paragrafo(rotulo: String, texto: String, cor: Color) -> void:
	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 0)

	var nome := Label.new()
	nome.text = rotulo
	nome.add_theme_font_size_override("font_size", 6)
	nome.add_theme_color_override("font_color", cor)
	caixa.add_child(nome)

	var linha := Label.new()
	linha.text = texto
	linha.add_theme_font_size_override("font_size", 7)
	linha.add_theme_color_override("font_color", Color("c3cad4"))
	linha.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	linha.custom_minimum_size = Vector2(conteudo.size.x, 0)
	caixa.add_child(linha)

	corpo.add_child(caixa)


## Depois de um quadro: o tamanho mínimo dos rótulos com quebra automática só fica
## conhecido quando eles já receberam largura.
func _encaixar() -> void:
	await get_tree().process_frame
	Encaixe.no_painel(painel, conteudo, 6.0)


func _ao_continuar() -> void:
	Audio.tocar("ui")
	_pagina = (_pagina + 1) % 3
	_montar()


func _ao_sair() -> void:
	Audio.tocar("ui")
	fechado.emit()
	get_tree().paused = false
	Audio.parar_musica(0.2)
	get_tree().change_scene_to_file("res://scenes/ui/tela_titulo.tscn")
