extends CanvasLayer

## Ranking global, consultável de qualquer máquina (Etapa 7 da Metodologia).
##
## É CanvasLayer e não Control porque a tela precisa servir a dois usos sem virar duas
## cenas: aberta sozinha a partir do título, e sobreposta à tela de resultado (que roda
## com a árvore pausada). Daí também o process_mode ALWAYS, gravado na cena.
##
## Mostra o ranking POR DIA: os três expedientes têm durações e tetos diferentes, e um
## placar único compararia coisas incomparáveis.
##
## A lista traz também a leitura por quadrante de cada partida — é o mesmo requisito de
## "notas por categoria" que a tela de resultado atende para a partida atual, e é o que
## impede o ranking de premiar só quem correu rápido.

## Emitido quando a tela é fechada estando sobreposta. Quem abriu se encarrega do resto.
signal fechado

const Encaixe := preload("res://scripts/encaixe.gd")

## Ligado por quem instancia a cena por cima de outra. Standalone (aberta pelo título),
## o botão Voltar troca de cena; sobreposta, ela só se remove.
var sobreposto := false

@onready var painel: Control = $Painel
@onready var conteudo: VBoxContainer = $Painel/Conteudo
@onready var origem: Label = $Painel/Conteudo/Origem
@onready var lista_dias: HBoxContainer = $Painel/Conteudo/Dias
@onready var linhas: VBoxContainer = $Painel/Conteudo/Linhas
@onready var botao_voltar: Button = $Painel/Conteudo/Botoes/Voltar
@onready var botao_atualizar: Button = $Painel/Conteudo/Botoes/Atualizar

var _dia := 1
var botoes_dia: Array[Button] = []


func _ready() -> void:
	_dia = clampi(GameManager.dia, 1, GameManager.CENA_DO_DIA.size())
	_montar_dias()
	_atualizar_dias()

	botao_voltar.pressed.connect(_ao_voltar)
	botao_atualizar.pressed.connect(_consultar)
	SupabaseClient.ranking_recebido.connect(_ao_receber)

	_consultar()
	botao_voltar.grab_focus()


## ESC fecha, como no menu de pausa. _unhandled_input e não sondagem: aqui não há
## percurso automatizado dirigindo teclas, e o evento evita fechar duas telas de uma vez.
func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("pausar"):
		get_viewport().set_input_as_handled()
		_ao_voltar()


## Um botão por expediente existente, gerado a partir da tabela do GameManager pelo mesmo
## motivo da tela de título: um dia novo não pode depender de alguém lembrar de abrir a
## cena e duplicar um botão.
##
## Aqui todos os dias ficam consultáveis, inclusive os que o jogador ainda não liberou —
## ver o placar de um dia que você ainda não jogou é convite, não espiada indevida.
func _montar_dias() -> void:
	var molde := lista_dias.get_child(0) as Button
	var dias: Array = GameManager.CENA_DO_DIA.keys()
	dias.sort()
	for numero in dias:
		var botao := molde if numero == dias[0] else molde.duplicate() as Button
		if botao != molde:
			lista_dias.add_child(botao)
		botao.pressed.connect(_ao_escolher_dia.bind(numero))
		botoes_dia.append(botao)


func _ao_escolher_dia(numero: int) -> void:
	if numero == _dia:
		return
	_dia = numero
	Audio.tocar("ui")
	_atualizar_dias()
	_consultar()


func _atualizar_dias() -> void:
	for i in botoes_dia.size():
		var numero := i + 1
		botoes_dia[i].set_pressed_no_signal(numero == _dia)
		botoes_dia[i].text = "Dia %d" % numero


func _consultar() -> void:
	origem.text = "consultando..."
	origem.add_theme_color_override("font_color", Color("7d878f"))
	SupabaseClient.pedir_ranking(_dia)


## A resposta chega por sinal, e não como retorno, porque a consulta é assíncrona quando
## há nuvem e síncrona quando não há. Um único caminho de chegada evita que a tela tenha
## duas formas de se preencher.
func _ao_receber(dados: Array, de_onde: String) -> void:
	if de_onde == "nuvem":
		origem.text = "ranking global · %s" % GameManager.NOME_DO_DIA[_dia].to_lower()
		origem.add_theme_color_override("font_color", Color("8fd6a8"))
	else:
		origem.text = "ranking local (sem conexão com a nuvem)"
		origem.add_theme_color_override("font_color", Color("ffb347"))

	for filho in linhas.get_children():
		linhas.remove_child(filho)
		filho.queue_free()

	if dados.is_empty():
		_vazio()
		_encaixar()
		return

	for i in dados.size():
		_adicionar(i + 1, dados[i] as Dictionary)
	_encaixar()


## Dez colocados não cabem no painel sem encolher o conjunto.
func _encaixar() -> void:
	await get_tree().process_frame
	Encaixe.no_painel(painel, conteudo, 6.0)


func _vazio() -> void:
	var aviso := Label.new()
	aviso.text = "Ninguém bateu o ponto neste dia ainda."
	aviso.add_theme_font_size_override("font_size", 7)
	aviso.add_theme_color_override("font_color", Color("7d878f"))
	aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	linhas.add_child(aviso)


func _adicionar(posicao: int, dado: Dictionary) -> void:
	var nome := str(dado.get("nickname", "?"))
	# Destacar a própria linha é o que transforma uma tabela num placar: sem isso o
	# jogador tem que procurar o próprio nome antes de sentir qualquer coisa.
	var meu := nome == Perfil.nickname
	var cor := Color("ffd166") if meu else Color("c3cad4")

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 6)

	linha.add_child(_celula("%d" % posicao, 16, Color("7d878f"), HORIZONTAL_ALIGNMENT_LEFT))
	linha.add_child(_celula(nome, 96, cor, HORIZONTAL_ALIGNMENT_LEFT))
	linha.add_child(_celula(
		"%d" % int(dado.get("pontuacao", 0)), 44, cor, HORIZONTAL_ALIGNMENT_RIGHT
	))
	linha.add_child(_quadrantes(dado))
	linha.add_child(_celula(
		_formatar(float(dado.get("tempo_gasto", 0.0))), 34, Color("7d878f"),
		HORIZONTAL_ALIGNMENT_RIGHT
	))

	linhas.add_child(linha)


## As quatro contagens, cada uma na cor do seu quadrante. Quatro rótulos coloridos em vez
## de um texto só: a cor é a mesma que a tarefa tem no HUD e na tela de resultado, então
## a leitura por categoria não precisa de legenda em lugar nenhum do jogo.
func _quadrantes(dado: Dictionary) -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 3)
	caixa.custom_minimum_size = Vector2(92, 0)
	caixa.alignment = BoxContainer.ALIGNMENT_CENTER

	var chaves := ["q1_tarefas", "q2_tarefas", "q3_tarefas", "q4_tarefas"]
	for i in chaves.size():
		var valor := Label.new()
		valor.text = "%d" % int(dado.get(chaves[i], 0))
		valor.add_theme_font_size_override("font_size", 7)
		valor.add_theme_color_override("font_color", GameManager.COR_CATEGORIA[i])
		valor.custom_minimum_size = Vector2(18, 0)
		valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caixa.add_child(valor)

	return caixa


func _celula(texto: String, largura: int, cor: Color, alinhamento: int) -> Label:
	var rotulo := Label.new()
	rotulo.text = texto
	rotulo.add_theme_font_size_override("font_size", 7)
	rotulo.add_theme_color_override("font_color", cor)
	rotulo.custom_minimum_size = Vector2(largura, 0)
	rotulo.horizontal_alignment = alinhamento
	rotulo.clip_text = true
	return rotulo


func _formatar(segundos: float) -> String:
	return "%02d:%02d" % [int(segundos) / 60, int(segundos) % 60]


func _ao_voltar() -> void:
	Audio.tocar("ui")
	if sobreposto:
		fechado.emit()
		queue_free()
		return
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/tela_titulo.tscn")
