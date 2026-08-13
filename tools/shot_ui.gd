extends Node

## Tira fotos das telas de interface — irmão de tools/screenshot.gd, que fotografa o
## corredor. Mesmo motivo de existir: no viewport de 400×208 um painel some, um texto
## estoura ou um botão encavala com facilidade, e nada disso aparece no teste headless.
##
## Como rodar (janela abre e fecha sozinha; NÃO use --headless, sem render não há foto):
##   godot --path . res://tools/shot_ui.tscn
## Os PNGs saem em user://shots_ui/ — o caminho absoluto é impresso no fim.

const DESTINO := "user://shots_ui/"
const QUADROS_DE_ESPERA := 10


func _ready() -> void:
	# A foto do menu de pausa é tirada com a árvore pausada; sem isto este próprio
	# nó pararia de rodar e a captura nunca aconteceria.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(DESTINO)

	# O ranking é lido de um arquivo descartável para que fotografar não misture partidas
	# de mentira no histórico real de quem estiver jogando nesta máquina.
	SupabaseClient.caminho_local = "user://shots_ranking.cfg"

	await _titulo_vazio()
	await _titulo_preenchido()
	await _briefing()
	await _pausa()
	await _resultado()
	await _derrota()
	await _licao()
	await _encerramento()
	await _ranking()

	print("PASTA: ", ProjectSettings.globalize_path(DESTINO))
	get_tree().quit()


## Estado em que o jogo abre pela primeira vez: sem crachá salvo, JOGAR desabilitado.
func _titulo_vazio() -> void:
	Perfil.nickname = ""
	await _fotografar_cena("res://scenes/ui/tela_titulo.tscn", "titulo_vazio.png")


## Estado de quem já jogou antes: campo pré-preenchido e botão liberado.
func _titulo_preenchido() -> void:
	Perfil.nickname = "Kleytonn"
	await _fotografar_cena("res://scenes/ui/tela_titulo.tscn", "titulo_preenchido.png")


## A pauta do dia, que é a primeira coisa que o jogador lê. Fotografada porque ela tem
## muita linha de texto num painel pequeno, e texto vazando de painel já aconteceu na
## tela de título.
func _briefing() -> void:
	var tela: Node = load("res://scenes/ui/briefing.tscn").instantiate()
	get_tree().root.add_child(tela)
	tela.montar(
		3,
		GameManager.NOME_DO_DIA[3],
		GameManager.TAREFAS_DO_DIA[3],
		int(GameManager.SEGUNDOS_DO_DIA[3]),
	)
	await _esperar()
	await _salvar("briefing.png")
	tela.queue_free()
	await get_tree().process_frame


## O menu por cima da fase de verdade, que é o único jeito de ver se ele cobre bem o
## HUD e se o painel não encavala com nada.
func _pausa() -> void:
	Perfil.nickname = "Kleytonn"
	var fase: Node = load("res://scenes/level/fase_01.tscn").instantiate()
	add_child(fase)
	await _esperar()

	fase.abrir_pausa()
	await _esperar()
	await _salvar("pausa.png")

	get_tree().paused = false
	fase.queue_free()
	await get_tree().process_frame


## A tela de resultado com uma partida plausível dentro. É a foto que mostra a leitura
## por quadrante, que é o resultado principal do jogo.
func _resultado() -> void:
	Perfil.nickname = "Kleytonn"
	var cat := GameManager.Categoria
	var acao := GameManager.Acao

	GameManager.iniciar_fase(90.0, 1)
	for i in 6:
		GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.IGNOROU)
	for i in 3:
		GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR)
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.DELEGAR)
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.RESOLVER)
	for i in 4:
		GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.EVITOU)
	GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.COLIDIU)
	GameManager.tempo_restante = 21.0
	GameManager.finalizar_fase(true)

	var tela: Node = load("res://scenes/ui/tela_resultado.tscn").instantiate()
	add_child(tela)
	tela.montar(true, {cat.URGENTE_IMPORTANTE: 7, cat.IMPORTANTE_NAO_URGENTE: 4,
		cat.URGENTE_NAO_IMPORTANTE: 2, cat.NAO_URGENTE_NAO_IMPORTANTE: 5})
	# Espera por TEMPO, e não por quadros: as linhas entram escalonadas por tween (cerca
	# de 0,8s no total) e contar quadros presume uma taxa que a máquina pode não dar, o
	# que fotografa a tabela ainda transparente.
	await get_tree().create_timer(1.5).timeout
	await _salvar("resultado.png")
	tela.queue_free()
	await get_tree().process_frame


## A derrota do último dia, que é a que mais linhas tem: relatório por quadrante mais as
## duas linhas extras da fase, tudo no mesmo painel.
func _derrota() -> void:
	_semear_partida(3)
	GameManager.finalizar_fase(false)

	var tela: Node = load("res://scenes/ui/tela_resultado.tscn").instantiate()
	add_child(tela)
	tela.montar(false, _composicao(), [
		["Pilha de pendências", "24 de 24"],
		["Fase do Chefe alcançada", "3 de 4"],
	], ["SOTERRADO PELAS PENDÊNCIAS",
		"a pilha tomou a sala antes de Kleytonn vencer o relógio. O dia foi perdido."])
	await get_tree().create_timer(1.5).timeout
	await _salvar("derrota.png")
	tela.queue_free()
	await get_tree().process_frame


## A explicação do erro, nas duas telas dela: o resumo e o detalhe de um quadrante.
func _licao() -> void:
	_semear_partida(3)
	GameManager.finalizar_fase(false)

	var tela: Node = load("res://scenes/ui/tela_licao.tscn").instantiate()
	add_child(tela)
	await _esperar()
	await _salvar("licao_resumo.png")
	tela._ao_detalhar()
	await _esperar()
	await _salvar("licao_detalhe.png")
	tela.queue_free()
	await get_tree().process_frame


## O encerramento, nas três páginas.
func _encerramento() -> void:
	_semear_partida(3)
	GameManager.finalizar_fase(true)

	var tela: Node = load("res://scenes/ui/tela_final.tscn").instantiate()
	add_child(tela)
	for i in 3:
		await _esperar()
		await _salvar("final_%d.png" % (i + 1))
		tela._ao_continuar()
	tela.queue_free()
	await get_tree().process_frame


## Partida plausível de um dia, para as telas de relatório terem número dentro.
func _semear_partida(dia: int) -> void:
	Perfil.nickname = "Kleytonn"
	var cat := GameManager.Categoria
	var acao := GameManager.Acao

	GameManager.iniciar_fase(GameManager.SEGUNDOS_DO_DIA[dia], dia)
	for i in 5:
		GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR, "Auditoria pede o relatório")
	for i in 3:
		GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.IGNOROU, "Servidor de produção fora do ar")
	for i in 2:
		GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR, "Documentar o processo")
	for i in 4:
		GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.IGNOROU, "Testar o backup antes que ele falhe sozinho")
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.DELEGAR, "Reunião de status sem pauta")
	for i in 2:
		GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.RESOLVER, "Preencher a planilha de outro time")
	for i in 6:
		GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.EVITOU, "Notificação de rede social")
	for i in 2:
		GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.COLIDIU, "Vídeo engraçado no grupo")
	GameManager.tempo_restante = 0.0


func _composicao() -> Dictionary:
	var cat := GameManager.Categoria
	return {
		cat.URGENTE_IMPORTANTE: 12, cat.IMPORTANTE_NAO_URGENTE: 9,
		cat.URGENTE_NAO_IMPORTANTE: 9, cat.NAO_URGENTE_NAO_IMPORTANTE: 14,
	}


## O ranking com gente dentro. Semeado à mão porque a tela vazia não mostra nada do que
## precisa ser conferido: alinhamento das colunas, corte do nickname longo, e as quatro
## contagens coloridas por quadrante cabendo na largura de 400px.
func _ranking() -> void:
	Perfil.nickname = "Kleytonn"
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(SupabaseClient.caminho_local)
	)
	var exemplos := [
		["Marina", 1180, 58.0, 7, 4, 2, 0],
		["Kleytonn", 1040, 66.5, 6, 3, 2, 1],
		["Rafa", 980, 71.0, 6, 2, 2, 1],
		["Bia", 860, 74.5, 5, 2, 1, 2],
		["nome-bem-comprido", 640, 82.0, 4, 1, 1, 3],
	]
	for e in exemplos:
		SupabaseClient.guardar_local({
			"nickname": e[0], "dia": 1, "vitoria": true, "pontuacao": e[1],
			"tempo_gasto": e[2], "q1_tarefas": e[3], "q2_tarefas": e[4],
			"q3_tarefas": e[5], "q4_tarefas": e[6],
		}, true)

	GameManager.dia = 1
	await _fotografar_cena("res://scenes/ui/tela_ranking.tscn", "ranking.png")


func _fotografar_cena(caminho: String, nome: String) -> void:
	var cena: Node = load(caminho).instantiate()
	add_child(cena)
	await _esperar()
	await _salvar(nome)
	cena.queue_free()
	await get_tree().process_frame


func _esperar() -> void:
	for i in QUADROS_DE_ESPERA:
		await get_tree().process_frame


func _salvar(nome: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(DESTINO + nome)
	print("salvo ", nome, " ", img.get_size())
