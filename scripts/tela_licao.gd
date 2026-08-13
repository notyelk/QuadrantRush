extends CanvasLayer

## Transforma o fim de partida em leitura da matriz: quais decisões saíram do quadrante
## certo, e por quê.
##
## Tem duas telas. A primeira agrupa os equívocos da partida por par categoria+ação e diz
## quantas vezes cada um aconteceu; "Entender o motivo" abre a explicação completa de um
## grupo por vez.
##
## Roda com process_mode ALWAYS: entra por cima da tela de resultado, com a árvore pausada.

signal fechado

const Encaixe := preload("res://scripts/encaixe.gd")
const Licoes := preload("res://scripts/licoes.gd")

## Quantos grupos cabem na lista sem espremer a leitura. Os mais frequentes primeiro —
## é o erro repetido que explica a derrota, não o que aconteceu uma vez.
const GRUPOS_NA_LISTA := 4

@onready var painel: Control = $Painel
@onready var conteudo: VBoxContainer = $Painel/Conteudo
@onready var titulo: Label = $Painel/Conteudo/Titulo
@onready var subtitulo: Label = $Painel/Conteudo/Subtitulo
@onready var corpo: VBoxContainer = $Painel/Conteudo/Corpo
@onready var botao_detalhar: Button = $Painel/Conteudo/Botoes/Detalhar
@onready var botao_voltar: Button = $Painel/Conteudo/Botoes/Voltar

var _grupos: Array[Dictionary] = []
var _detalhe := -1


func _ready() -> void:
	_grupos = _agrupar(GameManager.equivocos)
	botao_detalhar.pressed.connect(_ao_detalhar)
	botao_voltar.pressed.connect(_ao_voltar)
	_mostrar_resumo()
	botao_detalhar.grab_focus()


func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("pausar"):
		get_viewport().set_input_as_handled()
		_ao_voltar()


## Junta os equívocos iguais e devolve os mais frequentes primeiro, guardando um
## enunciado de exemplo para o jogador reconhecer a tarefa de que se está falando.
func _agrupar(lista: Array) -> Array[Dictionary]:
	var por_chave := {}
	for equivoco in lista:
		var chave := "%d:%d" % [int(equivoco["categoria"]), int(equivoco["acao"])]
		if not por_chave.has(chave):
			por_chave[chave] = {
				"categoria": int(equivoco["categoria"]),
				"acao": int(equivoco["acao"]),
				"vezes": 0,
				"exemplo": "",
			}
		por_chave[chave]["vezes"] += 1
		if por_chave[chave]["exemplo"].is_empty():
			por_chave[chave]["exemplo"] = str(equivoco["enunciado"])

	var grupos: Array[Dictionary] = []
	grupos.assign(por_chave.values())
	grupos.sort_custom(func(a, b) -> bool: return a["vezes"] > b["vezes"])
	return grupos


func _mostrar_resumo() -> void:
	_detalhe = -1
	_limpar()

	titulo.text = "POR QUE VOCÊ PERDEU?" if not GameManager.ultima_vitoria else "O QUE CUSTOU O SEU DIA"
	titulo.add_theme_color_override(
		"font_color", Color("8fd6a8") if GameManager.ultima_vitoria else Color("e05c5c")
	)

	if _grupos.is_empty():
		subtitulo.text = "Nenhuma tarefa saiu do quadrante certo. O que faltou foi tempo, não critério."
		botao_detalhar.visible = false
		_encaixar()
		return

	subtitulo.text = "%d decisões saíram do quadrante que a matriz indicava." % GameManager.equivocos.size()
	botao_detalhar.visible = true
	botao_detalhar.text = "Entender o motivo"

	for i in mini(_grupos.size(), GRUPOS_NA_LISTA):
		_linha_de_grupo(_grupos[i])
	_encaixar()


func _linha_de_grupo(grupo: Dictionary) -> void:
	var cor: Color = GameManager.COR_CATEGORIA[grupo["categoria"]]
	var explicacao := Licoes.para(grupo["categoria"], grupo["acao"])

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 6)

	var marca := ColorRect.new()
	marca.color = cor
	marca.custom_minimum_size = Vector2(3, 0)
	linha.add_child(marca)

	var vezes := Label.new()
	vezes.text = "%dx" % int(grupo["vezes"])
	vezes.add_theme_font_size_override("font_size", 7)
	vezes.add_theme_color_override("font_color", cor)
	vezes.custom_minimum_size = Vector2(18, 0)
	linha.add_child(vezes)

	var texto := Label.new()
	texto.text = str(explicacao["titulo"])
	texto.add_theme_font_size_override("font_size", 7)
	texto.add_theme_color_override("font_color", Color("c3cad4"))
	texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texto.clip_text = true
	linha.add_child(texto)

	corpo.add_child(linha)


func _mostrar_detalhe(indice: int) -> void:
	_detalhe = indice
	_limpar()

	var grupo := _grupos[indice]
	var cor: Color = GameManager.COR_CATEGORIA[grupo["categoria"]]
	var explicacao := Licoes.para(grupo["categoria"], grupo["acao"])

	titulo.text = str(explicacao["titulo"]).to_upper()
	titulo.add_theme_color_override("font_color", cor)
	subtitulo.text = GameManager.NOME_CATEGORIA[grupo["categoria"]]

	if not str(grupo["exemplo"]).is_empty():
		_paragrafo("NA SUA PARTIDA", "\"%s\"" % grupo["exemplo"], cor)
	_paragrafo("O QUE ACONTECEU", str(explicacao["o_que"]), Color("7d878f"))
	_paragrafo("O TRATAMENTO CERTO", str(explicacao["certo"]), Color("8fd6a8"))
	_paragrafo("POR QUÊ", str(explicacao["porque"]), Color("7d878f"))
	_paragrafo("NA MATRIZ", str(explicacao["conceito"]), Color("5aa9e6"))
	if not str(explicacao["exemplo"]).is_empty():
		_paragrafo("NO DIA A DIA", str(explicacao["exemplo"]), Color("7d878f"))

	var restam := indice + 1 < mini(_grupos.size(), GRUPOS_NA_LISTA)
	botao_detalhar.visible = true
	botao_detalhar.text = "Próximo erro" if restam else "Ver o resumo"
	_encaixar()


func _paragrafo(rotulo: String, texto: String, cor: Color) -> void:
	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 0)

	var nome := Label.new()
	nome.text = rotulo
	nome.add_theme_font_size_override("font_size", 6)
	nome.add_theme_color_override("font_color", cor)
	caixa.add_child(nome)

	var corpo_texto := Label.new()
	corpo_texto.text = texto
	corpo_texto.add_theme_font_size_override("font_size", 7)
	corpo_texto.add_theme_color_override("font_color", Color("c3cad4"))
	corpo_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	corpo_texto.custom_minimum_size = Vector2(conteudo.size.x, 0)
	caixa.add_child(corpo_texto)

	corpo.add_child(caixa)


func _limpar() -> void:
	for filho in corpo.get_children():
		corpo.remove_child(filho)
		filho.queue_free()


## Depois de um quadro: o tamanho mínimo dos rótulos com quebra automática só fica
## conhecido quando eles já receberam largura.
func _encaixar() -> void:
	await get_tree().process_frame
	Encaixe.no_painel(painel, conteudo, 6.0)


func _ao_detalhar() -> void:
	Audio.tocar("ui")
	if _detalhe < 0:
		_mostrar_detalhe(0)
		return
	var proximo := _detalhe + 1
	if proximo < mini(_grupos.size(), GRUPOS_NA_LISTA):
		_mostrar_detalhe(proximo)
	else:
		_mostrar_resumo()


func _ao_voltar() -> void:
	Audio.tocar("ui")
	fechado.emit()
	queue_free()
