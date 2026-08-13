extends Control

## Tela de título — Etapa 6 da Metodologia ("telas de título, com campo de
## nickname"). É a cena principal do projeto: o jogo passa a abrir aqui em vez de
## já sair correndo dentro da fase.
##
## Além de ser a porta de entrada, é aqui que a Etapa 7 ganha o dado que lhe falta.
## Sem nickname não há o que gravar no ranking, e a autenticação combinada na seção
## 3.1 é exatamente esta: um nome, sem senha.
##
## Desde que existe um segundo expediente, também é aqui que se escolhe o dia. O Dia 2
## fica trancado até a primeira vitória no Dia 1 — quem chega ao jogo pela primeira vez
## não deve poder pular a fase que ensina a mecânica.

@onready var campo: LineEdit = $Painel/Conteudo/Identificacao/Campo
@onready var aviso: Label = $Painel/Conteudo/Aviso
@onready var lista_dias: HBoxContainer = $Painel/Conteudo/Dias
## Preenchido em _montar_dias() a partir de GameManager.CENA_DO_DIA. Era uma lista
## fixa de botões escritos na cena; virou geração para que a tela nunca minta, porque
## a cada expediente novo alguém teria que lembrar de abrir a cena e duplicar um
## botão — e esquecer disso não quebra nada, só deixa a fase inacessível.
var botoes_dia: Array[Button] = []
@onready var botao_jogar: Button = $Painel/Conteudo/Botoes/Jogar
@onready var botao_ranking: Button = $Painel/Conteudo/Botoes/Ranking
@onready var botao_sair: Button = $Painel/Conteudo/Botoes/Sair

var _dia := 1


func _ready() -> void:
	campo.max_length = Perfil.MAXIMO
	campo.text = Perfil.nickname
	campo.text_changed.connect(_ao_digitar)
	campo.text_submitted.connect(_ao_enviar)

	# Abre já no dia mais avançado que o jogador liberou: quem voltou para jogar o Dia 2
	# não deveria ter que escolher de novo toda vez.
	_dia = Perfil.dia_liberado
	_montar_dias()
	_atualizar_dias()

	botao_jogar.pressed.connect(_ao_jogar)
	botao_ranking.pressed.connect(_ao_ranking)
	botao_sair.pressed.connect(_ao_sair)

	# Fechar a aba não é coisa que um jogo web faça, e a Etapa 9 exporta para WebGL.
	botao_sair.visible = not OS.has_feature("web")

	# A fase pausa a árvore ao terminar; voltar para cá com a árvore ainda pausada
	# deixaria esta tela congelada.
	get_tree().paused = false

	_atualizar_estado()
	campo.grab_focus()
	campo.caret_column = campo.text.length()


## A validação acontece na digitação, não no clique: o jogador descobre que o nome
## não serve enquanto ainda está olhando para o campo, em vez de apertar JOGAR e
## nada acontecer.
func _ao_digitar(_texto: String) -> void:
	_atualizar_estado()


func _ao_enviar(_texto: String) -> void:
	if not botao_jogar.disabled:
		_ao_jogar()


func _ao_escolher_dia(numero: int) -> void:
	if not Perfil.dia_esta_liberado(numero):
		return
	_dia = numero
	Audio.tocar("ui")
	_atualizar_dias()
	_atualizar_estado()


## Um botão por expediente existente. O primeiro botão da cena é o molde: os demais
## são duplicatas dele, o que herda tema, fonte e tamanho sem nada disso aparecer aqui.
func _montar_dias() -> void:
	var molde := lista_dias.get_child(0) as Button
	# Sobras de uma versão anterior da cena. Remover em vez de reaproveitar mantém a
	# lista sempre exatamente do tamanho da tabela de dias.
	for i in range(lista_dias.get_child_count() - 1, 0, -1):
		lista_dias.get_child(i).queue_free()
		lista_dias.remove_child(lista_dias.get_child(i))

	var dias: Array = GameManager.CENA_DO_DIA.keys()
	dias.sort()
	for numero in dias:
		var botao := molde if numero == dias[0] else molde.duplicate() as Button
		if botao != molde:
			lista_dias.add_child(botao)
		botao.pressed.connect(_ao_escolher_dia.bind(numero))
		botoes_dia.append(botao)


## Os botões são de alternância, mas sem ButtonGroup: manter o estado na mão evita
## versionar um .tres só para isso.
func _atualizar_dias() -> void:
	for i in botoes_dia.size():
		var numero := i + 1
		var liberado := Perfil.dia_esta_liberado(numero)
		botoes_dia[i].disabled = not liberado
		botoes_dia[i].set_pressed_no_signal(numero == _dia)
		botoes_dia[i].text = "Dia %d" % numero if liberado else "Dia %d (trancado)" % numero


func _atualizar_estado() -> void:
	var valido := not Perfil.validar(campo.text).is_empty()
	botao_jogar.disabled = not valido

	if campo.text.strip_edges().is_empty():
		aviso.text = "Digite um nome para bater o ponto."
	elif not valido:
		aviso.text = "O nome precisa ter de %d a %d caracteres." % [Perfil.MINIMO, Perfil.MAXIMO]
	else:
		aviso.text = "%s — %s" % [GameManager.NOME_DO_DIA[_dia], Perfil.validar(campo.text)]


const CENA_BRIEFING := preload("res://scenes/ui/briefing.tscn")


func _ao_jogar() -> void:
	if not Perfil.definir(campo.text):
		return
	# Grava antes de trocar de cena: se o jogador fechar o jogo no meio do
	# expediente, o nome dele continua aqui na próxima vez.
	Perfil.salvar()
	Audio.tocar("ui")
	_mostrar_briefing()


## A pauta do dia entra ANTES da fase, por cima da tela de título.
##
## A faixa do HUD não serve para isso: ela sobe junto com o cronômetro e some em poucos
## segundos. Como a mecânica da fase é ler a tarefa e decidir, o jogador precisa saber
## disso antes de o relógio começar.
func _mostrar_briefing() -> void:
	# Tira o foco do campo de crachá ANTES de abrir a pauta. Um LineEdit focado consome
	# as teclas, e o briefing fecha com "qualquer tecla" — sem isto, apertar qualquer
	# coisa digitaria no nome em vez de começar o expediente, e a tela travaria.
	campo.release_focus()

	var briefing: Control = CENA_BRIEFING.instantiate()
	add_child(briefing)
	briefing.montar(
		_dia,
		GameManager.NOME_DO_DIA[_dia],
		GameManager.TAREFAS_DO_DIA[_dia],
		int(GameManager.SEGUNDOS_DO_DIA[_dia]),
	)
	briefing.fechado.connect(func() -> void:
		Audio.tocar("ui")
		get_tree().change_scene_to_file(GameManager.CENA_DO_DIA[_dia])
	)


## O ranking é consultável sem jogar e sem nome válido: quem abre o jogo pela primeira vez
## deve poder ver contra o que vai competir antes de decidir se joga.
func _ao_ranking() -> void:
	Audio.tocar("ui")
	get_tree().change_scene_to_file("res://scenes/ui/tela_ranking.tscn")


func _ao_sair() -> void:
	Audio.tocar("ui")
	get_tree().quit()
