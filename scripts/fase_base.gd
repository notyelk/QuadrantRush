extends Node2D
class_name FaseBase

## O que todo expediente faz igual: checkpoint, queda no vão, pausa, tique do relógio,
## som por ação da matriz e disparo da tela de resultado.
##
## O que cada fase tem de próprio fica nas sobrescritas: duração, cota do elevador, o
## que existe no corredor e o que ela liga no _ready.
##
## Pontuação e cronômetro moram no GameManager, não aqui.
##
## Toda cena de fase precisa ter, com estes nomes: Player, HUD, Saida, Tarefas,
## Bifurcacoes, Checkpoints, ZonaDeQueda e Inimigos.

## Segundos cobrados por cair num vão. A fase não é letal — nenhum inimigo mata nem
## reinicia o expediente. A punição é tempo, que é a moeda do jogo, em vez de uma tela
## de morte que quebraria o ritmo.
const CUSTO_QUEDA := 5.0

## Abaixo disto o relógio começa a tiquetaquear.
const TEMPO_CRITICO := 15.0

const CENA_RESULTADO := preload("res://scenes/ui/tela_resultado.tscn")
const CENA_PAUSA := preload("res://scenes/ui/menu_pausa.tscn")
const Enunciados := preload("res://scripts/enunciados.gd")

## Qual efeito toca para cada ação da matriz. Tabela em vez de match espalhado: a
## lista de ações é fechada (é o Quadro 1), e vê-la inteira num lugar só torna óbvio
## se alguma ficou muda.
const SOM_DA_ACAO := {
	GameManager.Acao.COLETAR: "coleta",
	GameManager.Acao.DELEGAR: "delegar",
	GameManager.Acao.RESOLVER: "coleta",
	GameManager.Acao.EVITOU: "ui",
	GameManager.Acao.COLIDIU: "erro",
	GameManager.Acao.IGNOROU: "ignorou",
}

@onready var jogador: CharacterBody2D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var saida: Node2D = $Saida
@onready var tarefas: Node2D = $Tarefas
@onready var bifurcacoes: Node2D = $Bifurcacoes
@onready var checkpoints: Node2D = $Checkpoints
@onready var zona_de_queda: Area2D = $ZonaDeQueda
@onready var inimigos: Node2D = $Inimigos

## Quantas tarefas de cada categoria a fase contém — alimenta o "X de N" da tela de
## resultado e a trava do elevador.
var composicao: Dictionary = {}

var _q1_coletadas := 0
var _ultimo_checkpoint := Vector2.ZERO
var _terminou := false
var _perigo: Node2D = null
var _pausa: CanvasLayer = null
var _proximo_tique := 0.0
## Extremos do percurso projetados no eixo de avanço, para o HUD desenhar a barra de
## progresso sem precisar saber a geometria da fase.
var _progresso_inicial := 0.0
var _progresso_final := 1.0
var _eixo := Vector2.RIGHT
## Qual setor de setores() ainda não foi anunciado.
var _setor_atual := 0


# O que cada fase responde por si

## Duração do expediente, em segundos.
func tempo_de_expediente() -> float:
	return GameManager.TEMPO_PADRAO_FASE


## Este dia usa a pasta (peso do trabalho em andamento)? Falso por padrão de propósito.
##
## A pasta só é justa num corredor que tenha caixas de saída; ligá-la numa fase sem elas
## seria penalidade sem antídoto. É por isso que a decisão fica com cada dia, e não numa
## constante global.
func usa_pasta() -> bool:
	return false


## Este dia oferece o modo foco? Falso por padrão, pelo mesmo motivo da pasta: quem não
## declara continua exatamente como estava. Os dois expedientes o oferecem — é habilidade
## aprendida, e habilidade aprendida não se perde de um dia para o outro.
func usa_foco() -> bool:
	return false


## Qual dia do jogo é este. Vai para o GameManager e daí para o resultado.
func numero_do_dia() -> int:
	return 1


## Zerar o relógio é VITÓRIA nesta fase? Falso por padrão: nos Dias 1 e 2 o tempo é a
## ameaça, e quem não declara continua exatamente como estava.
##
## O Dia 3 inverte: lá o expediente é o que se sobrevive, e quem mata é a pilha de
## pendências. Ver scripts/pilha_pendencias.gd.
func vitoria_por_tempo() -> bool:
	return false


## Qual par de faixas toca nesta fase (ver Audio.iniciar_musica). Os dois expedientes
## usam "expediente"; o gancho continua aqui porque é onde uma fase futura o trocaria.
func conjunto_musical() -> String:
	return "expediente"


## Para que lado a fase "avança". Precisa ser unitário: o progresso é a projeção da posição
## neste vetor. Três coisas dependem dele — a barra de percurso do HUD, a regra de que um
## checkpoint só vale adiante do anterior, e o momento em que uma tarefa conta como deixada
## para trás (tarefa.gd), que é o que dispara Acao.IGNOROU e, no Dia 2, a maturação.
func eixo_de_avanco() -> Vector2:
	return Vector2.RIGHT


## Quanto uma posição do mundo "avançou" na fase. É a única conta que traduz geometria
## em progresso, e todo mundo passa por aqui.
func progresso(posicao: Vector2) -> float:
	return posicao.dot(_eixo)


## Quantas Q1 o elevador exige. O padrão é "todas as que existem" (Fase 1); a Fase 2
## usa cota, porque lá as tarefas chegam caindo e perder uma não pode trancar o dia.
##
## É uma FUNÇÃO, e não um número guardado no _ready, porque no Dia 2 a meta cresce
## durante o expediente: cada pendência adiada que amadurece acrescenta uma urgente
## obrigatória. Quem quiser mudar a meta em curso chama revisar_meta() depois.
func meta_de_urgentes() -> int:
	return int(composicao.get(GameManager.Categoria.URGENTE_IMPORTANTE, 0))


## Reapresenta a cota ao HUD e reavalia a trava do elevador.
##
## Chamado por quem mexe na meta no meio da fase. Retrancar importa: sem isso, adiar
## depois de já ter cumprido a cota sairia de graça, porque a porta já estaria aberta.
func revisar_meta() -> void:
	var meta := meta_de_urgentes()
	hud.atualizar_urgentes(_q1_coletadas, meta)
	saida.pendentes = maxi(meta - _q1_coletadas, 0)
	if _q1_coletadas >= meta:
		saida.liberar()
	else:
		saida.trancar()


## Frase da faixa do HUD ao abrir: [título, texto, cor].
func abertura() -> Array:
	return [
		"EXPEDIENTE INICIADO",
		"Leia cada tarefa e decida: encostar é fazer agora, passar é deixar para lá.",
		Color("8fd6a8"),
	]


## Linhas extras da tela de resultado, no formato [[rótulo, valor], ...]. Vazio no
## padrão; o Dia 2 devolve por aqui quantas pendências viraram crise.
func extras_do_resultado() -> Array:
	return []


## Título e frase da tela de resultado: [titulo, texto].
##
## Fica na fase porque perder não quer dizer a mesma coisa em toda parte — no Dia 3 o
## relógio zerado é vitória, e anunciar "tempo esgotado" lá diria o contrário do que
## aconteceu.
func fecho(vitoria: bool) -> Array:
	var quem := Perfil.nickname if not Perfil.nickname.is_empty() else "Você"
	if vitoria:
		return [
			"EXPEDIENTE CONCLUÍDO",
			"%s saiu no horário, com %s de sobra." % [quem, _relogio(GameManager.tempo_restante)],
		]
	return [
		"DIA PERDIDO",
		"o expediente acabou antes de %s chegar ao elevador." % quem,
	]


func _relogio(segundos: float) -> String:
	return "%02d:%02d" % [int(segundos) / 60, int(segundos) % 60]


## Os trechos em que o expediente se divide, anunciados ao jogador quando ele entra em
## cada um: [{"em": progresso, "nome": String, "dica": String}], em ordem.
##
## Os setores sempre existiram na geometria, mas sem anúncio o jogador via um corredor
## uniforme. Nomeá-los não muda geometria, tempo nem pontuação: é só leitura.
func setores() -> Array:
	return []


## Gancho chamado no _ready, antes de o cronômetro começar. É onde uma fase liga o que
## só ela tem (o spawner do Dia 2, por exemplo).
func _preparar() -> void:
	pass


## Gancho chamado a cada quadro enquanto a fase está em curso.
func _atualizar(_delta: float) -> void:
	pass


## Troca o enunciado de cada tarefa parada do corredor por um sorteado do mesmo quadrante.
##
## As tarefas que CAEM (Dia 2) sacam do mesmo saco na hora de nascer, em
## spawner_tarefas.gd — por isso o embaralhamento acontece antes de _preparar().
func _sortear_enunciados() -> void:
	for tarefa in tarefas.get_children():
		if not "categoria" in tarefa:
			continue
		var sorteado := Enunciados.sacar(int(tarefa.categoria))
		# Só a tarefa que já amadurecia continua amadurecendo: ligar a maturação numa
		# fase que não a tem mudaria a composição do dia.
		if not String(tarefa.texto_maduro).is_empty():
			tarefa.texto_maduro = sorteado[1]
		tarefa.definir_texto(sorteado[0])

	for bifurcacao in bifurcacoes.get_children():
		if bifurcacao.has_method("definir_texto"):
			bifurcacao.definir_texto(
				Enunciados.sacar(GameManager.Categoria.URGENTE_NAO_IMPORTANTE)[0]
			)


# Orquestração comum

func _ready() -> void:
	# O grupo existe para que a tarefa descubra o eixo da fase sem que a fase precise
	# sair configurando cada tarefa uma a uma.
	add_to_group("fase")
	_eixo = eixo_de_avanco().normalized()

	_ultimo_checkpoint = jogador.global_position
	_progresso_inicial = progresso(jogador.global_position)
	_progresso_final = progresso(saida.global_position)

	Enunciados.embaralhar()
	_preparar()
	_sortear_enunciados()
	composicao = _mapear_composicao()

	for area in checkpoints.get_children():
		if area is Area2D:
			(area as Area2D).body_entered.connect(_ao_passar_checkpoint.bind(area as Area2D))

	zona_de_queda.body_entered.connect(_ao_cair)
	GameManager.tarefa_registrada.connect(_ao_registrar_tarefa)
	GameManager.fase_terminada.connect(_ao_terminar_fase)
	saida.alcancada.connect(_ao_alcancar_saida)

	_ligar_perigo()

	GameManager.iniciar_fase(tempo_de_expediente(), numero_do_dia())
	# Depois de iniciar_fase(), que devolve a pasta ao estado neutro. Cada dia declara se
	# usa a mecânica; quem não declara continua exatamente como estava.
	GameManager.pasta_em_uso = usa_pasta()
	GameManager.foco_disponivel = usa_foco()
	GameManager.vitoria_ao_esgotar_tempo = vitoria_por_tempo()
	Audio.iniciar_musica(conjunto_musical())
	hud.mostrar_pasta(usa_pasta())
	hud.atualizar_urgentes(0, meta_de_urgentes())
	saida.pendentes = meta_de_urgentes()
	hud.definir_percurso(_progresso_inicial, _progresso_final)

	var frase := abertura()
	get_tree().call_group("hud", "mostrar_dica", frase[0], frase[1], frase[2])


## A pausa é lida por sondagem, e não por _unhandled_input, pelo mesmo motivo que o
## pulo do jogador: Input.action_press() não sintetiza InputEvent, então o percurso
## automatizado do teste não conseguiria exercitar este caminho.
##
## Só a ABERTURA mora aqui. Este _process não roda com a árvore pausada, então quem
## escuta a tecla para FECHAR é o próprio menu, que tem process_mode ALWAYS.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pausar"):
		abrir_pausa()
	if _terminou:
		return
	hud.atualizar_percurso(progresso(jogador.global_position), _progresso_do_perigo())
	_tiquetaquear(delta)
	_anunciar_setor()
	_atualizar(delta)


## Anuncia o setor em que o jogador acabou de entrar.
##
## Só AVANÇA: voltar por um setor já visto não reanuncia nada, senão oscilar na fronteira
## encheria a faixa e cobriria o retorno das tarefas. Prioridade 1, a mais baixa: nome de
## setor é ambientação, e o que o jogador precisa ler para agir passa por cima dele.
func _anunciar_setor() -> void:
	var lista := setores()
	if _setor_atual >= lista.size():
		return
	var onde := progresso(jogador.global_position)
	while _setor_atual < lista.size() and onde >= float(lista[_setor_atual]["em"]):
		var setor: Dictionary = lista[_setor_atual]
		_setor_atual += 1
		get_tree().call_group(
			"hud", "mostrar_dica",
			str(setor["nome"]), str(setor.get("dica", "")),
			setor.get("cor", Color("8fd6a8")) as Color, 1
		)
		Audio.tocar("ui", -14.0)


## Quem decide se dá para pausar é a fase, não o menu: só aqui se sabe que o
## expediente ainda está em curso. Depois do fim, ESC não faz nada — pausar sobre a
## tela de resultado empilharia dois painéis.
func abrir_pausa() -> void:
	if _terminou or is_instance_valid(_pausa):
		return

	_pausa = CENA_PAUSA.instantiate()
	_pausa.continuar_pedido.connect(_fechar_pausa)
	add_child(_pausa)
	# Silencia a camada de perseguição: sem isso a música de urso continua correndo
	# por cima de um jogo parado.
	Audio.intensidade(0.0)
	get_tree().paused = true


func _fechar_pausa() -> void:
	if not is_instance_valid(_pausa):
		return
	_pausa.queue_free()
	_pausa = null
	get_tree().paused = false


## Liga a fonte de pressão da fase ao resto do jogo, se ela tiver uma. Quem publica
## `perigo_mudou(0..1)` entra no grupo "perigo", e música, HUD e câmera escutam daqui em
## vez de recalcular a distância cada um.
##
## Por grupo e não pelo nó "Prazo", porque nem toda fase tem perseguidor. O contrato é
## "quanto o jogador está em perigo", o que deixa a fonte trocável.
func _ligar_perigo() -> void:
	_perigo = get_tree().get_first_node_in_group("perigo") as Node2D
	if _perigo == null:
		return
	_perigo.perigo_mudou.connect(_ao_mudar_perigo)
	# Bote e despertar são do urso. Conectar só o que existe evita que uma fonte de
	# perigo futura precise inventar sinais que não usa.
	if _perigo.has_signal("vai_dar_o_bote"):
		_perigo.vai_dar_o_bote.connect(_ao_armar_bote)
	if _perigo.has_signal("acordou"):
		_perigo.acordou.connect(func() -> void: Juice.tremer(0.35))


func _ao_mudar_perigo(intensidade: float) -> void:
	Audio.intensidade(intensidade)
	hud.definir_perigo(intensidade)


## O bote é a única coisa da fase que pode custar 8 segundos sem aviso, então ele
## recebe o aviso mais forte que existe: tremor de câmera durante todo o telegrafo.
func _ao_armar_bote(aviso: float) -> void:
	Juice.tremer(0.45)
	get_tree().call_group("hud", "alertar_bote", aviso)


## is_instance_valid, e não `!= null`: o cenário de teste tira o perseguidor da cena
## depois que a fase já o conectou, e uma referência a nó liberado não vira null sozinha.
func _progresso_do_perigo() -> float:
	return progresso(_perigo.global_position) if is_instance_valid(_perigo) else -INF


## Tique de relógio nos últimos segundos, acelerando conforme o tempo acaba. É o
## aviso que funciona sem o jogador tirar os olhos da plataforma em que vai pousar.
func _tiquetaquear(delta: float) -> void:
	if not GameManager.em_jogo or GameManager.tempo_restante > TEMPO_CRITICO:
		return
	_proximo_tique -= delta
	if _proximo_tique > 0.0:
		return
	Audio.tocar("tique", -6.0, 0.02)
	# De 1s por tique aos 15s restantes até 0,25s por tique no fim.
	_proximo_tique = lerpf(0.25, 1.0, GameManager.tempo_restante / TEMPO_CRITICO)


## Conta as tarefas de cada categoria efetivamente presentes na cena, em vez de manter
## números fixos no script: mover ou apagar uma tarefa no editor não quebra o "X de N"
## nem a trava do elevador.
func _mapear_composicao() -> Dictionary:
	var mapa := {}
	for categoria in GameManager.Categoria.values():
		mapa[categoria] = 0

	for tarefa in tarefas.get_children():
		if "categoria" in tarefa:
			mapa[tarefa.categoria] += 1

	# Cada bifurcação é UMA tarefa Q3 — o jogador decide como resolvê-la, mas ela conta
	# uma vez só, tenha ele delegado ou resolvido.
	mapa[GameManager.Categoria.URGENTE_NAO_IMPORTANTE] += bifurcacoes.get_child_count()

	return mapa


func _ao_registrar_tarefa(categoria: int, acao: int, _pontos: int, _delta_tempo: float) -> void:
	if SOM_DA_ACAO.has(acao):
		# Desviar corretamente acontece muitas vezes por fase; se soasse no mesmo volume
		# da coleta, viraria ruído e roubaria a atenção do que importa.
		var volume := -18.0 if acao == GameManager.Acao.EVITOU else 0.0
		Audio.tocar(SOM_DA_ACAO[acao], volume)

	if categoria != GameManager.Categoria.URGENTE_IMPORTANTE or acao != GameManager.Acao.COLETAR:
		return

	_q1_coletadas += 1
	hud.atualizar_urgentes(_q1_coletadas, meta_de_urgentes())
	saida.pendentes = maxi(meta_de_urgentes() - _q1_coletadas, 0)

	if _q1_coletadas >= meta_de_urgentes():
		saida.liberar()
		Audio.tocar("porta")
		Feedback.onda(self, saida.global_position + Vector2(0, -20), Color("8fd6a8"), 70.0)


func _ao_passar_checkpoint(corpo: Node2D, area: Area2D) -> void:
	if not corpo.is_in_group("Player"):
		return
	# Só avança: voltar por um checkpoint anterior não deve mover o respawn para trás.
	# "Anterior" é medido no eixo da fase, não em X (ver eixo_de_avanco).
	if progresso(area.global_position) <= progresso(_ultimo_checkpoint):
		return
	_ultimo_checkpoint = area.global_position
	Audio.tocar("checkpoint", -6.0)
	Feedback.onda(self, area.global_position, Color("8fd6a8"), 30.0)


func _ao_cair(corpo: Node2D) -> void:
	if not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return
	devolver_ao_checkpoint(
		CUSTO_QUEDA, "VOLTOU AO CORREDOR",
		"Queda custou %d segundos." % int(CUSTO_QUEDA), Color("a06cd5")
	)


## Tira o jogador de onde ele não deveria estar e cobra em tempo. Continua separado de
## _ao_cair porque é o contrato genérico de "voltar e pagar em segundos" — qualquer
## hazard novo entra por aqui em vez de reimplementar o desconto.
func devolver_ao_checkpoint(custo: float, titulo: String, texto: String, cor: Color) -> void:
	jogador.velocity = Vector2.ZERO
	jogador.global_position = _ultimo_checkpoint
	GameManager.descontar_tempo(custo)
	Audio.tocar("dano", -4.0)
	Juice.impacto(0.7)
	Juice.flash(cor, 0.2)
	get_tree().call_group("hud", "mostrar_dica", titulo, texto, cor)


func _ao_alcancar_saida() -> void:
	Audio.tocar("porta")


func _ao_terminar_fase(vitoria: bool) -> void:
	if _terminou:
		return
	_terminou = true

	# O jogador para de responder antes da tela aparecer: sem isso ele continua
	# correndo por baixo do resultado, e um pulo tardio ainda dispararia som.
	jogador.controlavel = false
	jogador.velocity = Vector2.ZERO

	Audio.intensidade(0.0)
	Audio.parar_musica(0.5)
	Audio.tocar("vitoria" if vitoria else "derrota", 0.0, 0.0)
	Juice.flash(Color("ffffff") if vitoria else Color("ff6b6b"), 0.4)

	var tela := CENA_RESULTADO.instantiate()
	add_child(tela)
	tela.montar(vitoria, composicao, extras_do_resultado(), fecho(vitoria))
	# Pausa depois de montar: a tela roda com process_mode ALWAYS, o resto da fase não.
	get_tree().paused = true
