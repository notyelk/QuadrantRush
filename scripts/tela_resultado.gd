extends CanvasLayer

## Tela de fim de expediente — Etapa 6 ("tela de resultado").
##
## O ponto central dela não é o placar: é a LEITURA POR QUADRANTE, exigida pelo checklist
## institucional ("notas por categoria de tarefa, não só um placar agregado").
##
## Roda com process_mode ALWAYS porque a árvore fica pausada enquanto ela está
## visível; sem isso os botões não responderiam.

const CENA_RANKING := preload("res://scenes/ui/tela_ranking.tscn")
const CENA_LICAO := preload("res://scenes/ui/tela_licao.tscn")
const CENA_FINAL := preload("res://scenes/ui/tela_final.tscn")
const Encaixe := preload("res://scripts/encaixe.gd")

@onready var painel: Control = $Painel
@onready var conteudo: VBoxContainer = $Painel/Conteudo
@onready var titulo: Label = $Painel/Conteudo/Titulo
@onready var subtitulo: Label = $Painel/Conteudo/Subtitulo
@onready var linhas: VBoxContainer = $Painel/Conteudo/Linhas
@onready var total: Label = $Painel/Conteudo/Total
@onready var envio: Label = $Painel/Conteudo/Envio
@onready var botao_repetir: Button = $Painel/Conteudo/Botoes/Principal/Repetir
@onready var botao_proximo: Button = $Painel/Conteudo/Botoes/Principal/Proximo
@onready var botao_encerramento: Button = $Painel/Conteudo/Botoes/Principal/Encerramento
@onready var botao_motivo: Button = $Painel/Conteudo/Botoes/Secundaria/Motivo
@onready var botao_ranking: Button = $Painel/Conteudo/Botoes/Secundaria/Ranking
@onready var botao_sair: Button = $Painel/Conteudo/Botoes/Secundaria/Sair

## Composição da fase, informada pela fase: quantas tarefas de cada categoria
## existiam. Sem isso não dá para dizer "3 de 4" — só "3".
var disponiveis: Dictionary = {}


func _ready() -> void:
	botao_repetir.pressed.connect(_ao_repetir)
	botao_proximo.pressed.connect(_ao_proximo)
	botao_encerramento.pressed.connect(_ao_encerramento)
	botao_motivo.pressed.connect(_ao_motivo)
	botao_ranking.pressed.connect(_ao_ranking)
	botao_sair.pressed.connect(_ao_sair)
	botao_repetir.grab_focus()


## Chamada por fase_01.gd logo depois de instanciar a cena.
## `extras` são linhas próprias da fase, no formato [[rótulo, valor], ...]. Existem
## por causa de números que não pontuam e mesmo assim importam (o Quadro 1
## do TCC lista o que pontua, e ele está protocolado) mas que precisa aparecer no
## relatório. Guardar isso no GameManager sujaria a leitura por categoria, que é
## exatamente o que o checklist institucional exige que fique limpo.
func montar(vitoria: bool, composicao: Dictionary, extras: Array = [], fecho: Array = []) -> void:
	disponiveis = composicao

	var nome_do_dia: String = GameManager.NOME_DO_DIA.get(GameManager.dia, "")
	var frases := fecho if fecho.size() >= 2 else _fecho_generico(vitoria)

	titulo.text = String(frases[0])
	titulo.add_theme_color_override(
		"font_color", Color("8fd6a8") if vitoria else Color("ff6b6b")
	)
	subtitulo.text = "%s — %s" % [nome_do_dia, frases[1]]

	_preparar_proximo_dia(vitoria)
	# Só aparece se houve o que explicar.
	botao_motivo.visible = not GameManager.equivocos.is_empty()

	for filho in linhas.get_children():
		filho.queue_free()

	_linha_q1()
	_linha_q2()
	_linha_q3()
	_linha_q4()
	_linha_interrupcoes()
	for extra in extras:
		_linha_simples(String(extra[0]), String(extra[1]), Color("ffb347"))

	total.text = "PONTUAÇÃO FINAL:  %d pts" % GameManager.pontuacao_total
	_registrar_no_ranking()
	_animar_entrada()
	_encaixar()


## Usado quando a fase não informa o próprio fecho.
func _fecho_generico(vitoria: bool) -> Array:
	var quem := Perfil.nickname if not Perfil.nickname.is_empty() else "Você"
	if vitoria:
		return [
			"EXPEDIENTE CONCLUÍDO",
			"%s saiu no horário, com %s de sobra." % [
				quem, _formatar(GameManager.tempo_restante)
			],
		]
	return ["DIA PERDIDO", "o expediente acabou antes de %s chegar ao elevador." % quem]


## O relatório cresce com a partida: extras da fase, linha de interrupções.
func _encaixar() -> void:
	await get_tree().process_frame
	Encaixe.no_painel(painel, conteudo, 6.0)


## Etapa 7: é aqui, e só aqui, que a partida vai para a nuvem — "grava nickname,
## pontuação e tempo ao fim da sessão", como a Metodologia descreve.
##
## Nunca bloqueia nada. Os botões já estão utilizáveis enquanto o envio acontece, e o
## resultado da tentativa aparece numa linha discreta. Um jogador que perdeu a conexão
## precisa poder jogar de novo, não esperar um timeout de rede.
func _registrar_no_ranking() -> void:
	envio.text = "registrando no ranking..."
	SupabaseClient.envio_concluido.connect(_ao_registrar, CONNECT_ONE_SHOT)
	SupabaseClient.enviar_partida()


func _ao_registrar(ok: bool, mensagem: String) -> void:
	envio.text = mensagem
	envio.add_theme_color_override("font_color", Color("8fd6a8") if ok else Color("7d878f"))


## As linhas por quadrante entram uma a uma, de cima para baixo.
##
## Não é enfeite: é aqui que o jogador descobre o que fez com cada quadrante. Mostrar as
## quatro linhas de uma vez faz o olho ir direto para o número final e pular a leitura
## por categoria; escalonar obriga a passar por cada quadrante antes do total.
##
## Todos os tempos são muito curtos (0,4s no total): é para guiar o olhar, não para
## fazer o jogador esperar antes de poder apertar "repetir".
func _animar_entrada() -> void:
	var painel: Control = $Painel
	painel.modulate.a = 0.0
	painel.scale = Vector2(0.94, 0.94)
	painel.pivot_offset = painel.size * 0.5

	var abertura := create_tween().set_parallel(true)
	abertura.tween_property(painel, "modulate:a", 1.0, 0.2)
	abertura.tween_property(painel, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for i in linhas.get_child_count():
		var linha: Control = linhas.get_child(i)
		linha.modulate.a = 0.0
		var t := create_tween()
		t.tween_interval(0.18 + 0.09 * i)
		t.tween_callback(func() -> void: Audio.tocar("ui", -10.0))
		t.tween_property(linha, "modulate:a", 1.0, 0.14)

	total.modulate.a = 0.0
	var fecho := create_tween()
	fecho.tween_interval(0.18 + 0.09 * linhas.get_child_count())
	fecho.tween_property(total, "modulate:a", 1.0, 0.2)


func _linha_q1() -> void:
	var cat := GameManager.Categoria.URGENTE_IMPORTANTE
	var n: int = GameManager.tarefas_por_categoria[cat]
	_adicionar(cat, "%d de %d coletadas" % [n, _disponivel(cat)], GameManager.pontuacao_por_categoria[cat])


func _linha_q2() -> void:
	var cat := GameManager.Categoria.IMPORTANTE_NAO_URGENTE
	var n: int = GameManager.tarefas_por_categoria[cat]
	_adicionar(cat, "%d de %d coletadas" % [n, _disponivel(cat)], GameManager.pontuacao_por_categoria[cat])


## Q3 é a única categoria com duas ações válidas, então a leitura útil não é "quantas", é
## "quantas você delegou em vez de resolver sozinho".
func _linha_q3() -> void:
	var cat := GameManager.Categoria.URGENTE_NAO_IMPORTANTE
	var delegou: int = GameManager.acoes_por_tipo[GameManager.Acao.DELEGAR]
	var resolveu: int = GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER]
	var ignorou: int = maxi(_disponivel(cat) - delegou - resolveu, 0)

	var texto := "%d delegadas, %d resolvidas" % [delegou, resolveu]
	if ignorou > 0:
		texto += ", %d não enfrentadas" % ignorou
	_adicionar(cat, texto, GameManager.pontuacao_por_categoria[cat])


func _linha_q4() -> void:
	var cat := GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE
	var evitou: int = GameManager.acoes_por_tipo[GameManager.Acao.EVITOU]
	var bateu: int = GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU]
	_adicionar(
		cat, "%d de %d evitadas (%d colisões)" % [evitou, _disponivel(cat), bateu],
		GameManager.pontuacao_por_categoria[cat]
	)


## Só aparece em fase que teve interrupção. Não vale ponto nenhum — é o dado que
## explica para onde o tempo foi, e é ele que o doc de 5 fases manda levar para o
## relatório final.
func _linha_interrupcoes() -> void:
	if GameManager.interrupcoes <= 0:
		return
	_linha_simples(
		"INTERRUPÇÕES", "%d vezes você parou para olhar" % GameManager.interrupcoes,
		Color("5aa9e6")
	)


## Linha de relatório que não é um quadrante da matriz: interrupções (Fase 2) e
## pendências que viraram crise (Dia 2). Mesma forma das outras para o olho não separar,
## mas sem coluna de pontos — porque elas não valem ponto, e mostrar um "0 pts" ao
## lado sugeriria que valem.
func _linha_simples(rotulo: String, detalhe: String, cor: Color) -> void:
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
	nome.custom_minimum_size = Vector2(112, 0)
	linha.add_child(nome)

	var meio := Label.new()
	meio.text = detalhe
	meio.add_theme_font_size_override("font_size", 7)
	meio.add_theme_color_override("font_color", Color("c3cad4"))
	meio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(meio)

	linhas.add_child(linha)


## Libera e oferece o dia seguinte. Só depois da VITÓRIA: perder e ganhar o próximo dia
## de graça tiraria o sentido de o elevador exigir as urgentes.
func _preparar_proximo_dia(vitoria: bool) -> void:
	var proximo: int = GameManager.dia + 1
	var existe: bool = GameManager.CENA_DO_DIA.has(proximo)

	if vitoria and existe:
		Perfil.liberar_dia(proximo)

	botao_proximo.visible = vitoria and existe
	if botao_proximo.visible:
		# Só o número do dia: o nome inteiro ("Dia 2 · O dia das interrupções") estourava
		# a largura do botão e empurrava a fileira para fora do painel.
		botao_proximo.text = "Ir para o Dia %d" % proximo
		botao_proximo.grab_focus()

	# Vencer o último expediente é o fim do jogo, e não mais um resultado igual aos
	# outros: o encerramento é onde a teoria que o jogo aplicou vira texto.
	botao_encerramento.visible = vitoria and not existe
	if botao_encerramento.visible:
		botao_encerramento.grab_focus()


func _adicionar(categoria: int, detalhe: String, pontos: int) -> void:
	var cor: Color = GameManager.COR_CATEGORIA[categoria]

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 6)

	var marca := ColorRect.new()
	marca.color = cor
	marca.custom_minimum_size = Vector2(3, 0)
	linha.add_child(marca)

	var nome := Label.new()
	nome.text = GameManager.NOME_CATEGORIA[categoria]
	nome.add_theme_font_size_override("font_size", 7)
	nome.add_theme_color_override("font_color", cor)
	nome.custom_minimum_size = Vector2(112, 0)
	linha.add_child(nome)

	var meio := Label.new()
	meio.text = detalhe
	meio.add_theme_font_size_override("font_size", 7)
	meio.add_theme_color_override("font_color", Color("c3cad4"))
	meio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(meio)

	var valor := Label.new()
	valor.text = "%+d" % pontos
	valor.add_theme_font_size_override("font_size", 7)
	valor.add_theme_color_override("font_color", Color("ffd166") if pontos >= 0 else Color("ff6b6b"))
	valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	valor.custom_minimum_size = Vector2(30, 0)
	linha.add_child(valor)

	linhas.add_child(linha)


func _disponivel(categoria: int) -> int:
	return int(disponiveis.get(categoria, 0))


func _formatar(segundos: float) -> String:
	return "%02d:%02d" % [int(segundos) / 60, int(segundos) % 60]


func _ao_repetir() -> void:
	Audio.tocar("ui")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _ao_proximo() -> void:
	var proximo: int = GameManager.dia + 1
	if not GameManager.CENA_DO_DIA.has(proximo):
		return
	Audio.tocar("ui")
	get_tree().paused = false
	get_tree().change_scene_to_file(GameManager.CENA_DO_DIA[proximo])


## O ranking entra POR CIMA do resultado, não no lugar dele: trocar de cena apagaria a
## leitura por quadrante que o jogador acabou de receber.
func _ao_ranking() -> void:
	Audio.tocar("ui")
	var tela := CENA_RANKING.instantiate()
	tela.sobreposto = true
	tela.fechado.connect(func() -> void: botao_repetir.grab_focus())
	add_child(tela)


func _ao_motivo() -> void:
	Audio.tocar("ui")
	var tela := CENA_LICAO.instantiate()
	tela.fechado.connect(func() -> void: botao_repetir.grab_focus())
	add_child(tela)


func _ao_encerramento() -> void:
	Audio.tocar("ui")
	var tela := CENA_FINAL.instantiate()
	tela.fechado.connect(func() -> void: botao_repetir.grab_focus())
	add_child(tela)


## Volta ao título em vez de fechar o jogo. get_tree().quit() não faz nada no export
## WebGL previsto na Etapa 9 — o botão era um no-op justamente na plataforma em que o
## jogo vai ser avaliado.
func _ao_sair() -> void:
	Audio.tocar("ui")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/tela_titulo.tscn")
