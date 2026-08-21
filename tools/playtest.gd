extends Node

## Roda os tres dias com perfis de jogador e escreve a tabela de resultados.
##
##   godot --headless --path . res://tools/playtest.tscn -- 5 dia=2
##
## O expediente corre em tempo real, entao rodar sem outra carga pesada na maquina.

const DESTINO := "res://docs/resultados_playtest.md"
const PARTIDAS_PADRAO := 3

# acerto: chance de ler o quadrante certo. desvio: sair da rota pelo Q2. impulso: ir
# atras do que classificou como distracao. foco: erra metade, anda a 65% enquanto le.
const PERFIS := [
	{
		"nome": "novato",
		"acerto": 0.50, "desvio": 0.35, "impulso": 0.35, "foco": false,
		"descricao": "Primeira partida. Lê pela metade, não descobriu o modo foco e vai"
			+ " atrás do que chama atenção.",
	},
	{
		"nome": "apagador de incêndio",
		"acerto": 0.85, "desvio": 0.05, "impulso": 0.10, "foco": false,
		"descricao": "Reconhece bem o que é urgente e trata tudo que grita, mas não sai da"
			+ " rota por algo que pode esperar.",
	},
	{
		"nome": "perfeccionista",
		"acerto": 0.75, "desvio": 1.00, "impulso": 0.55, "foco": true,
		"descricao": "Quer encostar em tudo que aparece, inclusive no que deveria deixar"
			+ " passar.",
	},
	{
		"nome": "apressado",
		"acerto": 0.60, "desvio": 0.00, "impulso": 0.15, "foco": false,
		"descricao": "Corre para o elevador e só trata o que está no caminho.",
	},
	{
		"nome": "estrategista",
		"acerto": 0.93, "desvio": 0.85, "impulso": 0.05, "foco": true,
		"descricao": "Lê antes de agir, delega o que dá para delegar e investe no que não é"
			+ " urgente enquanto há folga.",
	},
]

const DIAS := [1, 2, 3]

const VELOCIDADE := 180.0
const FATOR_FOCO := 0.65

# O dobro do raio do rotulo, que e o que o modo foco entrega.
const RAIO_DE_LEITURA := 192.0

# A origem do jogador fica acima da superficie em que ele pisa; entregar no canto exige
# chegar a essa altura, e nao a do piso.
const ALTURA_DOS_PES := 16.0

# Altura por onde contornar quando a reta esbarra em geometria.
const TRANSITO_CORREDOR := -24.0
const TRANSITO_ARENA := 56.0

# Quanto a frente o piloto enxerga tarefa. Mais do que isso seria onisciencia.
const JANELA := 300.0
const PASSO_ADIANTE := 140.0
const MAXIMO_DE_VOLTAS := 200

var resultados: Array = []

var _passo := 3.0
var _crencas := {}
var _decisoes := {}
var _alvo: Node = null
var _desistidos := {}


func _ready() -> void:
	_passo = VELOCIDADE / float(Engine.physics_ticks_per_second)

	# Partida de robo nao entra no ranking de ninguem.
	SupabaseClient.supabase_url = ""
	SupabaseClient.caminho_local = "user://playtest_ranking.cfg"
	Perfil.nickname = "simulacao"

	var partidas := PARTIDAS_PADRAO
	var dias := DIAS.duplicate()
	for argumento in OS.get_cmdline_user_args():
		if argumento.is_valid_int():
			partidas = maxi(int(argumento), 1)
		elif argumento.begins_with("dia="):
			dias = [int(argumento.trim_prefix("dia="))]

	print("perfis: %d | dias: %s | partidas por combinação: %d"
		% [PERFIS.size(), dias, partidas])

	for perfil in PERFIS:
		print("\n===== %s =====" % perfil["nome"])
		for dia in dias:
			var amostra: Array = []
			for n in partidas:
				amostra.append(await _partida(dia, perfil, n))
			resultados.append({"perfil": perfil, "dia": dia, "amostra": amostra})
			_relatar(dia, amostra)

	_escrever()
	get_tree().quit()


func _relatar(dia: int, amostra: Array) -> void:
	var vitorias := 0
	var soma := 0
	for r in amostra:
		soma += int(r["pontuacao"])
		if r["vitoria"]:
			vitorias += 1
	var r0: Dictionary = amostra[0]
	print("  dia %d: %d/%d concluídos, média %d pts | Q %s | ações %s | %.0fs"
		% [dia, vitorias, amostra.size(), soma / maxi(amostra.size(), 1),
			r0["por_categoria"], r0["acoes"], r0["tempo_gasto"]])


# Uma partida

func _partida(dia: int, perfil: Dictionary, semente: int) -> Dictionary:
	_crencas.clear()
	_decisoes.clear()
	_alvo = null
	_desistidos.clear()

	var rng := RandomNumberGenerator.new()
	# Duas execucoes do programa produzem os mesmos numeros.
	rng.seed = hash("%s|%d|%d" % [perfil["nome"], dia, semente])

	var fase := await _abrir(dia, semente)
	if dia == 3:
		await _pilotar_arena(fase, perfil, rng)
	else:
		await _pilotar_corredor(fase, perfil, rng)

	var placar := _placar(dia)
	await _fechar(fase)
	return placar


# Varredura, e nao rota montada de uma vez: no Dia 2 as tarefas so chegam conforme
# o jogador avanca.
func _pilotar_corredor(fase: Node2D, perfil: Dictionary, rng: RandomNumberGenerator) -> void:
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")
	var fim: float = fase.progresso(saida.global_position)
	var visitados := {}

	for volta in MAXIMO_DE_VOLTAS:
		if not GameManager.em_jogo:
			return

		var alvo := _alvo_do_corredor(fase, jogador, perfil, rng, visitados)
		if alvo != null:
			visitados[alvo.get_instance_id()] = true
			await _alcancar(jogador, alvo.global_position, perfil, TRANSITO_CORREDOR)
			# As tarefas do Dia 2 chegam caindo.
			await _esperar(6)
			continue

		if fase.progresso(jogador.global_position) >= fim:
			await _alcancar(jogador, saida.global_position, perfil, TRANSITO_CORREDOR)
			return

		await _ir(
			jogador,
			jogador.global_position + fase.eixo_de_avanco().normalized() * PASSO_ADIANTE,
			perfil
		)


# Distracao reconhecida como distracao nunca vira alvo: para ela, a acao correta e
# nao encostar.
func _alvo_do_corredor(fase: Node2D, jogador: CharacterBody2D, perfil: Dictionary,
		rng: RandomNumberGenerator, visitados: Dictionary) -> Node:
	var aqui: float = fase.progresso(jogador.global_position)
	var escolhido: Node = null
	var mais_perto := INF

	for tarefa in fase.get_node("Tarefas").get_children():
		if not ("categoria" in tarefa) or tarefa.esta_resolvida():
			continue
		if visitados.has(tarefa.get_instance_id()):
			continue
		var onde: float = fase.progresso(tarefa.global_position)
		# Tarefa ultrapassada nao volta a ser coletavel.
		if onde < aqui - 32.0 or onde > aqui + JANELA:
			continue
		if not _quer(tarefa, perfil, rng):
			continue
		if onde < mais_perto:
			mais_perto = onde
			escolhido = tarefa

	if escolhido != null:
		return escolhido

	# Sem nada por perto, sobe na bandeja: delegar vale +60 contra +40 de resolver.
	for bifurcacao in fase.get_node("Bifurcacoes").get_children():
		var ponto := bifurcacao.get_node_or_null("PontoDelegar")
		if ponto == null or visitados.has(ponto.get_instance_id()):
			continue
		var onde: float = fase.progresso(ponto.global_position)
		if onde < aqui - 8.0 or onde > aqui + JANELA:
			continue
		if rng.randf() < 0.4 + float(perfil["desvio"]) * 0.5:
			return ponto
	return null


func _pilotar_arena(fase: Node2D, perfil: Dictionary, rng: RandomNumberGenerator) -> void:
	var jogador: CharacterBody2D = fase.get_node("Player")

	for volta in MAXIMO_DE_VOLTAS * 4:
		if not GameManager.em_jogo:
			return

		var carregado := _papel_na_mao()
		if carregado != null:
			var canto := _canto_de(fase, _crenca(carregado, perfil, rng))
			if canto == null:
				return
			var alvo: Vector2 = canto.global_position - Vector2(0, ALTURA_DOS_PES)
			if not await _alcancar(jogador, alvo, perfil, TRANSITO_ARENA):
				# Canto inalcancavel: larga e busca outro em vez de esperar a validade vencer.
				await _largar_papel()
				continue
			# A entrega exige os pes no chao dentro do canto, e o piloto chega com o corpo no ar.
			await _esperar(24)
			continue

		var papel := _papel_mais_perto(jogador)
		if papel == null:
			await _esperar(20)
			continue
		var alcancou := await _alcancar(jogador, papel.global_position, perfil, TRANSITO_ARENA)
		if not alcancou and is_instance_valid(papel):
			_desistidos[papel.get_instance_id()] = true
		if not alcancou:
			_alvo = null
			continue
		await _esperar(6)


# A acao e lida por sondagem: pressionar e soltar em quadros distintos.
func _largar_papel() -> void:
	Input.action_press("largar")
	await get_tree().physics_frame
	Input.action_release("largar")
	await get_tree().physics_frame


func _canto_de(fase: Node2D, categoria: int) -> Node2D:
	for zona in fase.get_node("Zonas").get_children():
		if zona.papel == categoria:
			return zona
	return null


func _papel_na_mao() -> Node:
	for demanda in get_tree().get_nodes_in_group("demanda"):
		if demanda.carregada and not demanda.resolvida:
			return demanda
	return null


# Com histerese: sem ela, dois papeis equidistantes fazem o piloto oscilar no lugar.
func _papel_mais_perto(jogador: CharacterBody2D) -> Node:
	if is_instance_valid(_alvo) and not _alvo.resolvida and not _alvo.carregada:
		return _alvo

	_alvo = null
	var melhor: Node = null
	var distancia := INF
	for candidata in get_tree().get_nodes_in_group("demanda"):
		if not candidata._caiu or candidata.resolvida or candidata.carregada:
			continue
		if _desistidos.has(candidata.get_instance_id()):
			continue
		var d: float = jogador.global_position.distance_to(candidata.global_position)
		if d < distancia:
			distancia = d
			melhor = candidata
	_alvo = melhor
	return melhor


# Deslocamento

# Um destino atras de uma parede faz a fisica devolver o jogador a cada quadro; sem
# desistir, o piloto empurraria a mesma parede ate o expediente acabar.
const QUADROS_SEM_PROGRESSO := 30


# Reta e, se esbarrar, contorno por cima. O que a reta nao alcanca esta atras de uma
# parede ou de um degrau, e subir resolve os dois.
func _alcancar(jogador: CharacterBody2D, destino: Vector2, perfil: Dictionary,
		transito: float) -> bool:
	if await _ir(jogador, destino, perfil):
		return true
	if not await _ir(jogador, Vector2(jogador.global_position.x, transito), perfil):
		return false
	if not await _ir(jogador, Vector2(destino.x, transito), perfil):
		return false
	return await _ir(jogador, destino, perfil)


## Leva o piloto ao destino, e devolve falso se desistir no caminho.
##
## Passo curto porque Area2D so detecta em quadro de fisica. O tamanho dele e o que o
## jogador humano percorre no mesmo quadro, com o peso da pasta e o do papel na mao.
func _ir(jogador: CharacterBody2D, destino: Vector2, perfil: Dictionary) -> bool:
	var recorde := INF
	var parado := 0

	while GameManager.em_jogo:
		var aqui: float = jogador.global_position.distance_to(destino)
		if aqui <= _passo:
			jogador.global_position = destino
			jogador.velocity = Vector2.ZERO
			await get_tree().physics_frame
			return true

		if aqui < recorde - 0.5:
			recorde = aqui
			parado = 0
		else:
			parado += 1
			if parado > QUADROS_SEM_PROGRESSO:
				return false

		var avanco := _passo * GameManager.fator_da_pasta() * GameManager.fator_de_carga()
		if perfil["foco"] and aqui < RAIO_DE_LEITURA:
			avanco *= FATOR_FOCO

		jogador.global_position += (destino - jogador.global_position).normalized() * avanco
		jogador.velocity = Vector2.ZERO
		await get_tree().physics_frame

	return false


func _esperar(quadros: int) -> void:
	for i in quadros:
		if not GameManager.em_jogo:
			return
		await get_tree().physics_frame


# Leitura

# Sorteado uma vez por tarefa: quem leu errado continua errado ate agir.
func _crenca(tarefa: Node, perfil: Dictionary, rng: RandomNumberGenerator) -> int:
	var id := tarefa.get_instance_id()
	if _crencas.has(id):
		return _crencas[id]

	# O modo foco corta pela metade o que a pressa faz errar.
	var acerto: float = float(perfil["acerto"])
	if perfil["foco"]:
		acerto += (1.0 - acerto) * 0.5

	var verdade: int = tarefa.categoria
	var vista := verdade
	if rng.randf() > acerto:
		var outras := [0, 1, 2, 3]
		outras.erase(verdade)
		vista = outras[rng.randi() % outras.size()]
	_crencas[id] = vista
	return vista


# Decidido uma vez por tarefa: reconsiderar a cada volta faria o piloto ir e voltar.
func _quer(tarefa: Node, perfil: Dictionary, rng: RandomNumberGenerator) -> bool:
	var id := tarefa.get_instance_id()
	if _decisoes.has(id):
		return _decisoes[id]

	var quer := false
	match _crenca(tarefa, perfil, rng):
		GameManager.Categoria.URGENTE_IMPORTANTE:
			quer = true
		GameManager.Categoria.IMPORTANTE_NAO_URGENTE:
			quer = rng.randf() < float(perfil["desvio"])
		GameManager.Categoria.URGENTE_NAO_IMPORTANTE:
			quer = rng.randf() < 0.5 + float(perfil["desvio"]) * 0.5
		GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
			quer = rng.randf() < float(perfil["impulso"])
	_decisoes[id] = quer
	return quer


# Cena

func _abrir(dia: int, semente: int) -> Node2D:
	var fase: Node2D = load(GameManager.CENA_DO_DIA[dia]).instantiate()
	if "semente" in fase:
		fase.semente = absi(hash("arena|%d" % semente)) % 100000
	add_child(fase)
	await get_tree().process_frame
	await get_tree().process_frame
	return fase


func _fechar(fase: Node2D) -> void:
	get_tree().paused = false
	fase.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _placar(dia: int) -> Dictionary:
	return {
		"dia": dia,
		"pontuacao": GameManager.pontuacao_total,
		"tempo_gasto": GameManager.tempo_gasto if not GameManager.em_jogo
			else GameManager.SEGUNDOS_DO_DIA[dia] - GameManager.tempo_restante,
		"vitoria": GameManager.ultima_vitoria,
		"por_categoria": GameManager.tarefas_por_categoria.duplicate(),
		"acoes": GameManager.acoes_por_tipo.duplicate(),
	}


# Saída

func _escrever() -> void:
	var texto := _cabecalho()
	texto += _tabela_perfis()
	texto += _tabela_por_dia()
	texto += _tabela_por_quadrante()
	texto += _leitura()

	var arquivo := FileAccess.open(DESTINO, FileAccess.WRITE)
	if arquivo == null:
		print("não consegui escrever em ", DESTINO)
		return
	arquivo.store_string(texto)
	arquivo.close()
	print("\nescrito em ", ProjectSettings.globalize_path(DESTINO))


func _cabecalho() -> String:
	return """# Simulação de partidas por perfil de jogador

> **Gerado automaticamente** por `tools/playtest.gd`
> (`godot --headless --path . res://tools/playtest.tscn`). Não editar à mão: rode de novo.

> ## Estes números não são um playtest com pessoas
>
> Os cinco perfis abaixo são **agentes de software**. Eles jogam as fases de verdade, com a
> geometria, o relógio e as regras do jogo, e pagam o mesmo custo de tempo por pixel
> percorrido que um jogador humano paga — mas são programas, e a leitura de cada enunciado
> é modelada por uma probabilidade.
>
> **Nenhum número deste documento pode ser apresentado como desempenho humano nem como
> evidência de aprendizagem.** O playtest com pessoas é outro procedimento, previsto na
> etapa 8 da Metodologia, e continua pendente.
>
> O que a simulação demonstra é uma propriedade do **jogo**: que o placar responde à
> qualidade da priorização, e não à velocidade de percurso. Todos os perfis se deslocam à
> mesma velocidade; o que varia entre eles é o que decidem tratar.

"""


func _tabela_perfis() -> String:
	var texto := "## Os cinco perfis\n\n"
	texto += "| Perfil | Acerto de classificação | Sai da rota pelo Q2 | Vai atrás de distração | Modo foco |\n"
	texto += "|---|---|---|---|---|\n"
	for perfil in PERFIS:
		texto += "| %s | %d%% | %d%% | %d%% | %s |\n" % [
			perfil["nome"],
			int(round(float(perfil["acerto"]) * 100.0)),
			int(round(float(perfil["desvio"]) * 100.0)),
			int(round(float(perfil["impulso"]) * 100.0)),
			"sim" if perfil["foco"] else "não",
		]
	texto += "\n"
	for perfil in PERFIS:
		texto += "- **%s** — %s\n" % [perfil["nome"], perfil["descricao"]]
	texto += "\nO modo foco não aparece como acerto maior na coluna acima porque ele age "
	texto += "sobre o acerto de base: quem segura a tecla erra metade do que erraria, e "
	texto += "anda a 65% da velocidade enquanto lê. É o mesmo par de efeitos que a mecânica "
	texto += "entrega ao jogador.\n\n"
	return texto


func _tabela_por_dia() -> String:
	var texto := "## Resultado por perfil e por dia\n\n"
	texto += "| Perfil | Dia | Partidas | Concluiu | Pontuação média | Menor | Maior | Expediente médio |\n"
	texto += "|---|---|---|---|---|---|---|---|\n"
	for linha in resultados:
		var amostra: Array = linha["amostra"]
		var n := maxi(amostra.size(), 1)
		var soma := 0
		var menor := 1 << 30
		var maior := -(1 << 30)
		var vitorias := 0
		var tempo := 0.0
		for r in amostra:
			var p: int = int(r["pontuacao"])
			soma += p
			menor = mini(menor, p)
			maior = maxi(maior, p)
			tempo += float(r["tempo_gasto"])
			if r["vitoria"]:
				vitorias += 1
		texto += "| %s | %d | %d | %d de %d | %d pts | %d | %d | %.1fs |\n" % [
			linha["perfil"]["nome"], linha["dia"], amostra.size(),
			vitorias, amostra.size(), soma / n, menor, maior, tempo / n,
		]
	texto += "\n"
	return texto


# Nota por quadrante, que e a leitura que o jogo se propoe a produzir.
func _tabela_por_quadrante() -> String:
	var texto := "## Tarefas tratadas por quadrante (média das partidas)\n\n"
	texto += "| Perfil | Dia | Q1 | Q2 | Q3 | Q4 | Delegou | Colidiu | Deixou passar |\n"
	texto += "|---|---|---|---|---|---|---|---|---|\n"
	for linha in resultados:
		var amostra: Array = linha["amostra"]
		var n := maxi(amostra.size(), 1)
		var cat := [0, 0, 0, 0]
		var delegou := 0
		var colidiu := 0
		var passou := 0
		for r in amostra:
			for c in 4:
				cat[c] += int(r["por_categoria"][c])
			delegou += int(r["acoes"][GameManager.Acao.DELEGAR])
			colidiu += int(r["acoes"][GameManager.Acao.COLIDIU])
			passou += int(r["acoes"][GameManager.Acao.IGNOROU])
		texto += "| %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n" % [
			linha["perfil"]["nome"], linha["dia"],
			float(cat[0]) / n, float(cat[1]) / n, float(cat[2]) / n, float(cat[3]) / n,
			float(delegou) / n, float(colidiu) / n, float(passou) / n,
		]
	texto += "\nA coluna *Q4* conta as distrações em que o piloto encostou — para elas, a "
	texto += "ação correta é não encostar, e *Colidiu* é a mesma informação vista pelo lado "
	texto += "da penalidade.\n\n"
	return texto


func _leitura() -> String:
	return """## Como ler estas tabelas

Como todos os perfis se deslocam à mesma velocidade e pagam o mesmo relógio por pixel, a
diferença entre dois placares da mesma linha de dia só pode vir de decisão: o que cada um
escolheu tratar, e o que cada um classificou errado.

Três leituras que a simulação sustenta:

1. **Classificar mal custa duas vezes.** Quem confunde uma distração com trabalho paga a
   penalidade do Quadro 1 e ainda gasta o percurso até ela.
2. **Concluir o expediente depende do quadrante urgente, não do total de tarefas.** O
   elevador só abre depois da cota de urgentes: um perfil com pontuação intermediária pode
   não concluir o dia enquanto outro, mais seletivo, conclui.
3. **Investir no importante e não urgente rende mais no Dia 2.** É onde a pendência adiada
   amadurece, volta como crise e eleva a cota do elevador.

## Limites desta simulação

- Os pilotos não aprendem entre partidas. Um humano que joga o mesmo dia duas vezes
  reconhece enunciados e melhora; nenhuma linha aqui mede isso.
- A leitura de cada enunciado é modelada por uma probabilidade única. Um enunciado ambíguo
  e um óbvio têm o mesmo peso, o que a experiência de uma pessoa não teria.
- Os pilotos se deslocam por trajeto guiado, e não por navegação livre: eles não erram o
  pulo nem caem no vão. O que a geometria das fases cobra de habilidade motora está
  coberto pelas suítes em `tests/`, que atravessam os corredores com as teclas reais.
- O teto de pontuação de cada dia continua sendo o da caracterização das fases, em
  `resultados_testes.md`, e não o maior valor observado aqui.
"""
