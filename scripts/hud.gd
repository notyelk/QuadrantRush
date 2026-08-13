extends CanvasLayer

## HUD do expediente: tempo, pontuação e a faixa de retorno da última tarefa.
##
## A faixa mostra o enunciado ao se aproximar, sem o quadrante, e revela o quadrante
## depois da ação. Uma linha por vez, sempre no mesmo lugar: em 400x208px, balões sobre
## cada tarefa cobririam a ação.
##
## Só lê o GameManager e escuta sinais; nunca alcança dentro da fase. Está no grupo "hud"
## para receber mensagens por get_tree().call_group("hud", "mostrar_dica", ...).

## Segundos que uma mensagem fica na faixa antes de sumir.
const DURACAO_MENSAGEM := 2.6

## Abaixo disso o relógio fica vermelho e pulsa.
const TEMPO_CRITICO := 15.0

## Largura útil da barra de percurso, em pixels de viewport.
const LARGURA_PERCURSO := 388.0

@onready var rotulo_tempo: Label = $Topo/Tempo
@onready var rotulo_pontos: Label = $Topo/Pontos
@onready var rotulo_urgentes: Label = $Topo/Urgentes
@onready var rotulo_interrupcoes: Label = $Topo/Interrupcoes
@onready var rotulo_pasta: Label = $Topo/Pasta
@onready var faixa: Control = $Faixa
@onready var faixa_cor: ColorRect = $Faixa/Borda
@onready var faixa_titulo: Label = $Faixa/Titulo
@onready var faixa_texto: Label = $Faixa/Texto
@onready var vinheta: TextureRect = $Vinheta
@onready var veu_foco: TextureRect = $Foco
@onready var alerta: Label = $Alerta
@onready var barra_andado: ColorRect = $Topo/Percurso/Andado
@onready var marca_jogador: ColorRect = $Topo/Percurso/MarcaJogador
@onready var marca_prazo: ColorRect = $Topo/Percurso/MarcaPrazo

var _restante_mensagem := 0.0
var _prioridade_atual := 0
var _pulsando_tempo := false
var _inicio := 0.0
var _fim := 1.0
var _perigo := 0.0
## O placar mostrado corre atrás do placar real em vez de saltar. Ver _process.
var _pontos_exibidos := 0.0
var _pontos_alvo := 0
## A dica da pasta aparece uma vez por partida, quando ela passa a doer.
var _ensinou_pasta := false
## Carga do quadro anterior, para saber se o peso subiu ou foi entregue.
var _carga_anterior := 0


func _ready() -> void:
	add_to_group("hud")
	faixa.modulate.a = 0.0

	GameManager.pontuacao_mudou.connect(_ao_mudar_pontuacao)
	GameManager.tempo_mudou.connect(_ao_mudar_tempo)
	GameManager.tarefa_registrada.connect(_ao_registrar_tarefa)
	GameManager.carga_mudou.connect(_ao_mudar_carga)
	GameManager.foco_mudou.connect(_ao_mudar_foco)
	veu_foco.modulate.a = 0.0

	_ao_mudar_pontuacao(GameManager.pontuacao_total)
	_ao_mudar_tempo(GameManager.tempo_restante)
	atualizar_urgentes(0, 0)
	atualizar_interrupcoes(0)
	mostrar_pasta(false)


func _process(delta: float) -> void:
	_correr_placar(delta)

	if _restante_mensagem > 0.0:
		_restante_mensagem -= delta
		if _restante_mensagem <= 0.0:
			_prioridade_atual = 0
			var sumir := create_tween()
			sumir.tween_property(faixa, "modulate:a", 0.0, 0.25)


## O número não pula de 0 para 100: ele corre. Um contador que se move prende o olho
## por meio segundo e faz os 100 pontos PARECEREM cem pontos — saltar direto para o
## valor final é a mesma informação sem nenhuma recompensa.
func _correr_placar(delta: float) -> void:
	if int(_pontos_exibidos) == _pontos_alvo:
		return
	# Velocidade proporcional à diferença, com piso: ganhos grandes correm rápido,
	# os pequenos não ficam lentos demais.
	var diferenca := float(_pontos_alvo) - _pontos_exibidos
	var passo := maxf(absf(diferenca) * 7.0, 90.0) * delta
	_pontos_exibidos = move_toward(_pontos_exibidos, float(_pontos_alvo), passo)
	rotulo_pontos.text = "%d pts" % int(round(_pontos_exibidos))


## Mensagem de contexto (aproximação de tarefa, elevador trancado, ladrão de tempo).
## Chamada de fora via get_tree().call_group("hud", "mostrar_dica", ...).
##
## `prioridade` resolve o atropelo de mensagens. Correndo pelo enxame de Q4, seis
## "desviou da distração" chegavam em menos de dois segundos e cada um apagava o
## anterior — inclusive a mensagem da tarefa que o jogador tinha acabado de errar,
## que é justamente a que ele precisava ler. Agora uma mensagem de prioridade menor
## não interrompe uma maior que ainda está no ar; só ocupa a faixa se ela estiver
## livre ou se a de lá já estiver acabando.
func mostrar_dica(titulo: String, texto: String, cor: Color, prioridade: int = 1) -> void:
	if prioridade < _prioridade_atual and _restante_mensagem > 0.6:
		return

	faixa_titulo.text = titulo
	faixa_titulo.add_theme_color_override("font_color", cor)
	faixa_texto.text = texto
	faixa_cor.color = cor

	_prioridade_atual = prioridade
	_restante_mensagem = DURACAO_MENSAGEM
	var aparecer := create_tween()
	aparecer.tween_property(faixa, "modulate:a", 1.0, 0.12)


## Contador "Urgentes: 2/4" — a fase informa, o HUD só desenha.
func atualizar_urgentes(coletadas: int, total: int) -> void:
	if total <= 0:
		rotulo_urgentes.text = ""
		return
	rotulo_urgentes.text = "Urgentes %d/%d" % [coletadas, total]
	rotulo_urgentes.add_theme_color_override(
		"font_color",
		Color("8fd6a8") if coletadas >= total else GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE]
	)
	# Um pulinho no contador: é a confirmação de que a coleta CONTOU para abrir a
	# saída, que é a informação mais importante do jogo depois do tempo.
	var t := create_tween()
	t.tween_property(rotulo_urgentes, "scale", Vector2(1.35, 1.35), 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(rotulo_urgentes, "scale", Vector2.ONE, 0.14)


## Contador de interrupções (Fase 2). Fica escondido enquanto for zero: numa fase sem
## notificação nenhuma, um "Interrupções 0" parado no alto seria ruído permanente.
##
## É informativo e não penaliza pontuação — mas é o número que o doc de 5 fases pede
## para o relatório, e o que deixa o jogador perceber onde o tempo foi embora.
func atualizar_interrupcoes(total: int) -> void:
	if total <= 0:
		rotulo_interrupcoes.text = ""
		return
	rotulo_interrupcoes.text = "Interrupções %d" % total

	var t := create_tween()
	t.tween_property(rotulo_interrupcoes, "scale", Vector2(1.3, 1.3), 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(rotulo_interrupcoes, "scale", Vector2.ONE, 0.14)


## Extremos do percurso, já projetados no eixo de avanço da fase pela própria fase
## (ver FaseBase.eixo_de_avanco). São escalares, e não coordenadas X, porque uma fase
## sobe: lá o começo e o fim diferem principalmente em Y, e uma barra que lesse X
## marcaria a escalada inteira como "quase parado".
func definir_percurso(inicio: float, fim: float) -> void:
	_inicio = inicio
	_fim = maxf(fim, inicio + 1.0)


func atualizar_percurso(progresso_jogador: float, progresso_perigo: float) -> void:
	var pj := _fracao(progresso_jogador)
	barra_andado.size.x = LARGURA_PERCURSO * pj
	marca_jogador.position.x = LARGURA_PERCURSO * pj - 1.0

	if progresso_perigo == -INF:
		marca_prazo.visible = false
		return
	marca_prazo.visible = true
	marca_prazo.position.x = LARGURA_PERCURSO * _fracao(progresso_perigo) - 1.0


func _fracao(progresso: float) -> float:
	return clampf((progresso - _inicio) / (_fim - _inicio), 0.0, 1.0)


## 0 = urso longe, 1 = em cima. Escurece as bordas e acende a marca dele na barra.
func definir_perigo(intensidade: float) -> void:
	_perigo = clampf(intensidade, 0.0, 1.0)
	# Só começa a aparecer a partir da metade: uma vinheta sempre ligada vira parte
	# do cenário e para de comunicar.
	var visivel := clampf((_perigo - 0.45) / 0.55, 0.0, 1.0)
	var t := create_tween()
	t.tween_property(vinheta, "modulate:a", visivel, 0.25)
	marca_prazo.color = Color("ff6b6b").lerp(Color("ffffff"), _perigo * 0.5)


## Aviso do bote, com a duração do telegrafo. Aparece, pulsa e some sozinho.
func alertar_bote(aviso: float) -> void:
	alerta.text = "ATRÁS DE VOCÊ"
	alerta.scale = Vector2(0.7, 0.7)
	alerta.pivot_offset = alerta.size * 0.5

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(alerta, "modulate:a", 1.0, 0.08)
	t.tween_property(alerta, "scale", Vector2(1.1, 1.1), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(alerta, "scale", Vector2.ONE, 0.1)
	t.chain().tween_interval(aviso)
	t.chain().tween_property(alerta, "modulate:a", 0.0, 0.2)


func _ao_mudar_pontuacao(total: int) -> void:
	_pontos_alvo = total
	# Ganhou pontos: o rótulo salta. Perdeu: fica vermelho por um instante. São
	# leituras diferentes porque as consequências são diferentes.
	var ganhou := float(total) > _pontos_exibidos
	var t := create_tween()
	if ganhou:
		t.tween_property(rotulo_pontos, "scale", Vector2(1.25, 1.25), 0.09) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(rotulo_pontos, "scale", Vector2.ONE, 0.13)
	else:
		rotulo_pontos.add_theme_color_override("font_color", Color("ff6b6b"))
		t.tween_interval(0.35)
		t.tween_callback(func() -> void:
			rotulo_pontos.add_theme_color_override("font_color", Color("ffd166"))
		)


func _ao_mudar_tempo(restante: float) -> void:
	var minutos := int(restante) / 60
	var segundos := int(restante) % 60
	rotulo_tempo.text = "%02d:%02d" % [minutos, segundos]

	var critico := restante <= TEMPO_CRITICO
	rotulo_tempo.add_theme_color_override(
		"font_color", Color("ff6b6b") if critico else Color("e8ecf1")
	)
	if critico and not _pulsando_tempo:
		_pulsando_tempo = true
		var pulso := create_tween().set_loops()
		pulso.tween_property(rotulo_tempo, "modulate:a", 0.45, 0.35)
		pulso.tween_property(rotulo_tempo, "modulate:a", 1.0, 0.35)


## Mensagem de resultado, montada a partir do sinal do GameManager. Concentrar isso
## aqui (em vez de cada tarefa mandar a sua) garante que toda ação da matriz seja
## relatada do mesmo jeito, inclusive as que ainda não existem.
func _ao_registrar_tarefa(categoria: int, acao: int, pontos: int, delta_tempo: float) -> void:
	var efeito := "%+d pts" % pontos
	if delta_tempo != 0.0:
		efeito += "   %ds" % int(delta_tempo)

	# Desviar corretamente de uma distração é a ação mais frequente da fase (seis Q4)
	# e a menos informativa — o jogador já sabe que acertou porque nada aconteceu.
	# Fica em prioridade baixa para não roubar a faixa de um erro que ele precisa ler.
	var prioridade := 0 if acao == GameManager.Acao.EVITOU else 2

	# É AQUI que o quadrante é revelado. Enquanto a tarefa está no corredor o jogador
	# vê só o enunciado dela; o nome e a cor do quadrante aparecem depois que ele
	# decidiu, para que a resposta venha como correção e não como gabarito.
	mostrar_dica(
		GameManager.NOME_CATEGORIA[categoria],
		"%s   %s" % [GameManager.licao(categoria, acao), efeito],
		GameManager.COR_CATEGORIA[categoria],
		prioridade
	)


## Liga ou desliga o indicador da pasta. Chamado pela fase: só o Dia 1 usa a mecânica, e
## um contador parado em zero nas outras fases seria ruído puro.
##
## Ocupa a mesma vaga do contador de interrupções porque nenhum dia usa os dois: a pasta
## é do Dia 1 e as interrupções são do Dia 2. Duas vagas separadas custariam largura numa
## barra de 400px que já está cheia.
func mostrar_pasta(ativo: bool) -> void:
	rotulo_pasta.visible = ativo
	_ensinou_pasta = false
	if ativo:
		_ao_mudar_carga(GameManager.carga_da_pasta)


func _ao_mudar_carga(carga: int) -> void:
	if not rotulo_pasta.visible:
		return

	# Um contador que só troca de número passa despercebido no canto da tela. O salto
	# marca o instante em que o peso mudou, que é a informação que o jogador precisa
	# ligar à tarefa que acabou de fazer.
	_pulsar_pasta(Color("8fd6a8") if carga < _carga_anterior else Color("e0a35c"))
	_carga_anterior = carga

	if carga <= 0:
		rotulo_pasta.text = "Pasta vazia"
		rotulo_pasta.add_theme_color_override("font_color", Color("b9c0e0"))
		return

	# A porcentagem aparece porque o número sozinho não diz nada: "Pasta 3" não informa
	# que o jogador está 15% mais lento, e sem essa informação ele não tem como decidir se
	# vale desviar até a caixa de saída. O custo precisa estar na tela para ser escolha.
	var perda := int(round((1.0 - GameManager.fator_da_pasta()) * 100.0))
	rotulo_pasta.text = "Pasta %d  -%d%%" % [carga, perda]

	# A pasta não entra no cartão de abertura: seria a quinta regra de um cartão que já
	# tem quatro, e ninguém decora cinco regras antes de jogar. Ela se explica na hora em
	# que passa a doer, que é quando o jogador tem motivo para prestar atenção.
	if carga >= 2 and not _ensinou_pasta:
		_ensinou_pasta = true
		mostrar_dica("SUA PASTA", "O que você faz e não entrega vira peso. "
			+ "Deixe na caixa de saída para voltar ao ritmo.", Color("b9c0e0"), 2)

	var saturada := carga >= GameManager.PASTA_LIMITE
	rotulo_pasta.add_theme_color_override(
		"font_color", Color("e0a35c") if saturada else Color("b9c0e0"))


## Salto do contador da pasta, com um lampejo na cor do que aconteceu: âmbar quando o
## peso sobe, verde quando ele é entregue.
func _pulsar_pasta(cor: Color) -> void:
	rotulo_pasta.pivot_offset = rotulo_pasta.size * 0.5
	rotulo_pasta.add_theme_color_override("font_color", cor)

	var salto := create_tween()
	salto.tween_property(rotulo_pasta, "scale", Vector2(1.35, 1.35), 0.08) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	salto.tween_property(rotulo_pasta, "scale", Vector2.ONE, 0.18) 		.set_trans(Tween.TRANS_SINE)


## Visão de túnel enquanto o jogador está concentrado.
##
## Existe porque o modo foco muda o estado do MUNDO — as distrações deixam de acertar —
## e uma mudança de estado invisível é uma mudança que o jogador não sabe que fez. Ele
## precisa reconhecer de relance em qual dos dois modos está, sem olhar para o rodapé.
##
## Começou como um filtro azul chapado sobre a tela inteira e foi trocado por isto depois
## de olhar as duas capturas lado a lado: sobre uma paleta que já é azul-arroxeada, o
## filtro sumia. Escurecer as BORDAS, além de aparecer, diz a coisa certa — concentração
## é estreitar o campo de visão, não pintar o mundo de azul.
func _ao_mudar_foco(ativo: bool) -> void:
	var aparecer := create_tween()
	aparecer.tween_property(veu_foco, "modulate:a", 1.0 if ativo else 0.0, 0.15)
	Audio.abafar(ativo)
