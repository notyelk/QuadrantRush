extends Node2D

## Tira fotos da fase rodando de verdade, em pontos fixos do corredor.
##
## Por que existe: escolher coordenada de atlas e cor no escuro já produziu tile
## quebrado mais de uma vez neste projeto, e o teste headless só prova lógica. Aqui a
## fase é instanciada de verdade, o jogador é teleportado para
## cada ponto da lista e o viewport é salvo em PNG, que dá para abrir e olhar.
##
## Como rodar (janela abre e fecha sozinha; NÃO use --headless, sem render não há foto):
##   godot --path . res://tools/screenshot.tscn                 # Fase 1
##   godot --path . res://tools/screenshot.tscn -- fase_02      # Fase 2
## Os PNGs saem em user:// — o caminho absoluto é impresso no fim.

## Pontos do corredor de cada fase, em coordenadas de mundo. A altura importa: fotografar
## tudo na altura do piso esconderia justamente as plataformas altas e as tarefas de
## bônus, que são onde mora o desafio das duas fases.
const PONTOS_POR_FASE := {
	# O corredor tem 3.040px, com mezanino, colegas e a escada que só aparece depois de
	# delegar. Mexer na geometria da fase pede refazer estes pontos.
	"fase_01": [
		Vector2(200, 160),    # S0 recepção: tutorial, primeira Q1 e a Q4 gêmea dela
		Vector2(700, 130),    # S1 baias: esporão da primeira Q2
		Vector2(1050, 148),   # S1 primeira caixa de saída da pasta (ao lado dela)
		Vector2(1160, 120),   # S2 copa: bifurcação Q3 #1 e o colega sentado na bandeja
		Vector2(1450, 60),    # S3 mezanino: as duas primeiras Q2 do alto
		Vector2(1760, 150),   # S3 chão: a Q1 da auditoria, que trava quem ficou em cima
		Vector2(2000, 160),   # S3 chão: onde o colega #1 vai parar
		Vector2(2320, 120),   # S4 bandeja da Q3 #2
		Vector2(2500, 120),   # S4 bandeja da Q3 #3
		Vector2(2720, 110),   # S5 escada fantasma + a prateleira da última Q2
		Vector2(2960, 150),   # S5 última Q1 e o elevador
	],
	# O corredor tem 2.816px, com colegas, duas estruturas delegáveis e os pontos onde
	# as crises nascem.
	"fase_02": [
		Vector2(200, 160),    # S0 recepção: parede, janela e a cidade ao fundo
		Vector2(560, 100),    # S1 a primeira Q2, lá em cima, fora da linha de corrida
		Vector2(960, 118),    # S2 bandeja da Q3a com o colega sentado
		Vector2(1180, 118),   # S2 bandeja da Q3b
		Vector2(1430, 150),   # S3 o primeiro vão e a ponte fantasma
		Vector2(1640, 100),   # S3 a segunda Q2, sobre a plataforma alta
		Vector2(1900, 140),   # S4 a escada fantasma do arquivo
		Vector2(1990, 70),    # S4 a Q2 do alto: só existe para quem delegou
		Vector2(2130, 150),   # S4 o silêncio do arquivo
		Vector2(2410, 100),   # S5 a última Q2
		Vector2(2600, 130),   # S5 ponto de crise do fim do corredor
		Vector2(2760, 150),   # S6 elevador
	],
	# A Fase 3 não é corredor: é uma arena de 640x208 vista quase inteira. Os pontos aqui
	# não percorrem um caminho — eles enquadram os quatro cantos da matriz, que são
	# SORTEADOS a cada partida. Por isso a foto da Fase 3 tem de ser lida junto do
	# `layout` impresso no console: o mesmo ponto mostra quadrantes diferentes a cada
	# execução, e é exatamente esse o comportamento que se quer conferir.
	"fase_03": [
		Vector2(320, 150),    # centro do piso: a sala inteira, com o Chefe no pódio
		Vector2(88, 130),     # pedestal esquerdo: o canto de baixo daquele lado
		Vector2(552, 130),    # pedestal direito
		Vector2(152, 76),     # mezanino esquerdo: o canto de cima
		Vector2(488, 76),     # mezanino direito
		Vector2(320, 60),     # altura do Chefe, para conferir que ele é inalcançável
	],
}

const DESTINO := "user://shots/"

## Quadros esperados antes de cada foto. Precisa ser generoso: várias coisas da fase
## só ficam com a aparência final depois de um tween (halo das tarefas, barra do HUD,
## luz da saída), e uma foto tirada no primeiro quadro pega tudo no estado inicial.
const QUADROS_DE_ESPERA := 8


func _ready() -> void:
	# Qual fase fotografar vem da linha de comando, depois de "--". Sem argumento,
	# continua sendo a Fase 1 — assim o comando antigo segue funcionando.
	var qual := "fase_01"
	var argumentos := OS.get_cmdline_user_args()
	if not argumentos.is_empty() and PONTOS_POR_FASE.has(argumentos[0]):
		qual = argumentos[0]
	var PONTOS: Array = PONTOS_POR_FASE[qual]
	print("fotografando ", qual)

	DirAccess.make_dir_recursive_absolute(DESTINO)
	var fase: Node = load("res://scenes/level/%s.tscn" % qual).instantiate()
	add_child(fase)
	await get_tree().process_frame

	var player: Node2D = get_tree().get_first_node_in_group("Player")
	# Sem isto o jogador cai/anda entre a teleportação e a foto, e a câmera com
	# look-ahead sai deslocada do ponto pedido.
	player.controlavel = false
	# E sem DESLIGAR a física dele a gravidade continua puxando durante os quadros de
	# espera: vários pontos de foto ficam no ar, e sem isto o jogador cai antes do clique.
	player.set_physics_process(false)

	var cam: Camera2D = _achar_camera(fase)
	if cam:
		# Sem isso a câmera chega atrasada no ponto e a foto sai do lugar errado.
		cam.position_smoothing_enabled = false

	# Numa fase sorteada, a foto sozinha não diz nada: o mesmo ponto mostra quadrantes
	# diferentes a cada execução. Imprimir o layout é o que torna a captura interpretável:
	# sem ele, uma foto estranha não se distingue de um defeito de cenário.
	if "layout" in fase and not (fase.layout as Dictionary).is_empty():
		print("  semente: ", fase.layout["semente"])
		for categoria in fase.layout["cantos"]:
			print("  canto %-24s em %s" % [
				GameManager.NOME_CATEGORIA[categoria], fase.layout["cantos"][categoria]
			])
		for degrau in fase.layout["degraus"] as Array[Rect2]:
			print("  degrau ", degrau)

	for ponto in PONTOS:
		player.global_position = ponto
		player.velocity = Vector2.ZERO
		if cam:
			cam.force_update_scroll()
		for i in QUADROS_DE_ESPERA:
			player.velocity = Vector2.ZERO
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(DESTINO + "%s_%04d_%03d.png" % [qual, int(ponto.x), int(ponto.y)])
		print("salvo ", ponto, " ", img.get_size())

	await _retrato_do_urso(fase, player, cam)
	await _retrato_do_foco(fase, player, cam)

	print("PASTA: ", ProjectSettings.globalize_path(DESTINO))
	get_tree().quit()


## Foto do urso ao lado do jogador. Ele nasce no começo do corredor e leva mais de um
## minuto para aparecer, então nas fotos normais ele nunca sai — e ele é o principal
## adversário da fase, justamente o que mais precisa ser conferido de perto (lado para
## onde o sprite olha, tamanho relativo, leitura contra o fundo).
func _retrato_do_urso(fase: Node, player: Node2D, cam: Camera2D) -> void:
	if not fase.has_node("Inimigos/Prazo"):
		return
	var urso: Node2D = fase.get_node("Inimigos/Prazo")
	# Os dois sentidos: ele persegue para os dois lados, e já saiu errado uma vez
	# (corria de costas). Uma foto só não pega isso.
	for lado in [1, -1]:
		player.global_position = Vector2(1000, 160)
		urso.global_position = Vector2(1000 - 60 * lado, 176)
		if cam:
			cam.force_update_scroll()
		for i in QUADROS_DE_ESPERA:
			player.velocity = Vector2.ZERO
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var nome := "urso_direita.png" if lado > 0 else "urso_esquerda.png"
		get_viewport().get_texture().get_image().save_png(DESTINO + nome)
		print("salvo ", nome)


## Duas fotos do mesmo ponto, com e sem o modo foco. O foco muda o estado do mundo (as
## distrações param de acertar) e o único sinal disso é o véu azulado e o raio maior de
## leitura — coisas que só dá para julgar olhando lado a lado.
func _retrato_do_foco(fase: Node, player: Node2D, cam: Camera2D) -> void:
	if not fase.has_method("usa_foco") or not fase.usa_foco():
		return
	for ligado in [false, true]:
		# Forçado no GameManager, e não pela tecla: o jogador está com `controlavel`
		# desligado para a foto não sair borrada, e sem controle ele não lê entrada.
		GameManager.foco_disponivel = true
		GameManager.foco_ativo = ligado
		GameManager.foco_mudou.emit(ligado)
		player.global_position = Vector2(380, 150)
		if cam:
			cam.force_update_scroll()
		for i in QUADROS_DE_ESPERA * 3:
			player.velocity = Vector2.ZERO
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var nome := "foco_ligado.png" if ligado else "foco_desligado.png"
		get_viewport().get_texture().get_image().save_png(DESTINO + nome)
		print("salvo ", nome)


func _achar_camera(no: Node) -> Camera2D:
	if no is Camera2D:
		return no
	for f in no.get_children():
		var r := _achar_camera(f)
		if r:
			return r
	return null
