extends Node

## Gera a tabela quantitativa de resultados.
##
##   godot --headless --path . res://tools/metricas.tscn
##
## MEDE O JOGO, NÃO JOGADORES: os perfis são robôs determinísticos, e os números
## caracterizam o espaço de resultados possíveis, não desempenho humano. O documento
## gerado repete esse aviso, para não se perder ao copiar a tabela.
##
##   ATENTO    trata toda tarefa que vale ponto e desvia das distrações. É o teto.
##   APRESSADO corre direto para a saída, sem desviar. É o piso.

const DESTINO := "res://docs/resultados_testes.md"

## Por fase: cena, e a que altura o robô trafega entre uma tarefa e outra.
##
## A altura de trânsito existe para o robô não colher, de passagem, uma tarefa que um
## humano naquele percurso não tocaria — o mesmo cuidado que as duas suítes já tomavam.
const FASES := [
	{"dia": 1, "cena": "res://scenes/level/fase_01.tscn", "transito": -24.0},
	{"dia": 2, "cena": "res://scenes/level/fase_02.tscn", "transito": -24.0},
]

## Pontos por tarefa tratada corretamente, direto do Quadro 1 da Metodologia. Usado só
## para calcular o teto teórico; quem pontua de verdade é o GameManager.
const PONTOS_IDEAIS := {
	GameManager.Categoria.URGENTE_IMPORTANTE: 100,
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: 80,
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: 60,
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: 0,
}

const NOME_CURTO := {0: "Q1", 1: "Q2", 2: "Q3", 3: "Q4"}

var linhas: Array = []


func _ready() -> void:
	# Ver a nota nos testes: a tela de resultado grava no ranking local, e medir não pode
	# encher o histórico de quem joga nesta máquina.
	SupabaseClient.caminho_local = "user://metricas_ranking.cfg"
	SupabaseClient.supabase_url = ""
	Perfil.caminho = "user://metricas_perfil.cfg"
	Perfil.nickname = "robo"

	for fase in FASES:
		await _medir(fase)

	_escrever()
	get_tree().quit()


func _medir(config: Dictionary) -> void:
	print("\n===== Dia %d =====" % config["dia"])

	var estatica := await _caracterizar(config)
	var atento := await _rodar(config, true)
	var apressado := await _rodar(config, false)

	linhas.append({
		"dia": config["dia"],
		"estatica": estatica,
		"atento": atento,
		"apressado": apressado,
	})


## Números que não dependem de jogar: o que a fase contém e o que ela exige.
func _caracterizar(config: Dictionary) -> Dictionary:
	var fase := await _abrir(config)

	var teto := 0
	for categoria in fase.composicao:
		teto += int(fase.composicao[categoria]) * int(PONTOS_IDEAIS[categoria])

	var dados := {
		"composicao": fase.composicao.duplicate(),
		"teto": teto,
		"meta": fase.meta_de_urgentes(),
		"expediente": fase.tempo_de_expediente(),
		"percurso": absf(
			fase.progresso(fase.get_node("Saida").global_position)
			- fase.progresso(fase.get_node("Player").global_position)
		),
	}

	print("  composição: %s | teto teórico: %d pts | elevador exige %d urgentes"
		% [dados["composicao"], teto, dados["meta"]])
	await _fechar(fase)
	return dados


## Roda um perfil e devolve o que o GameManager registrou. `atento` escolhe entre os dois
## comportamentos descritos no topo do arquivo.
func _rodar(config: Dictionary, atento: bool) -> Dictionary:
	var fase := await _abrir(config)
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")
	var transito: float = config["transito"]

	if atento:
		await _varrer(fase, jogador, saida, transito)

	if GameManager.em_jogo:
		await _ir(jogador, saida.global_position, transito)
		for i in 20:
			await get_tree().physics_frame

	var resultado := _fotografar_placar()
	print("  %-9s %5d pts em %5.1fs  %s" % [
		"atento:" if atento else "apressado:",
		resultado["pontuacao"], resultado["tempo_gasto"],
		"concluiu" if resultado["vitoria"] else "não concluiu",
	])
	await _fechar(fase)
	return resultado


## Avanço em varredura, e não uma lista de destinos montada de uma vez.
##
## É o que a Fase 2 exige: lá as tarefas não existem no início — elas chegam conforme o
## jogador avança, disparadas por POSIÇÃO. Uma rota calculada no primeiro quadro veria
## quatro tarefas e ignoraria as outras doze, medindo 400 de 1140 pontos — número que
## diria mais sobre o robô do que sobre o jogo.
##
## O laço tem teto de iterações porque ele é dirigido pelo estado da cena: se alguma
## tarefa ficasse fora de alcance por um defeito, a alternativa seria rodar para sempre.
const PASSO_DE_VARREDURA := 140.0
const JANELA := 220.0
const MAXIMO_DE_VOLTAS := 120


func _varrer(fase: Node2D, jogador: CharacterBody2D, saida: Node2D, transito: float) -> void:
	# Tipo explícito: fase é um Node2D genérico aqui, então progresso() volta sem tipo e
	# o inferidor recusa o `:=`.
	var fim: float = fase.progresso(saida.global_position)
	# Um alvo já visitado não entra de novo na rota. Sem isso, uma tarefa que o toque não
	# resolve (uma bifurcação já decidida, por exemplo) fazia o robô voltar a ela em cada
	# volta do laço — a varredura não travava, mas levava minutos.
	var visitados := {}

	for volta in MAXIMO_DE_VOLTAS:
		# O expediente acabou (venceu ou o tempo esgotou): daqui para a frente nada mais
		# é registrado e a árvore está pausada. Sem esta saída o laço roda contra uma fase
		# morta até estourar o limite de voltas.
		if not GameManager.em_jogo:
			return

		var aqui: float = fase.progresso(jogador.global_position)
		var pendentes := _roteiro(fase)

		# Só o que já está ao alcance: correr até o fim da fase para buscar uma tarefa
		# que ainda não nasceu não é o que um jogador faria.
		var agora: Array = pendentes.filter(func(p: Vector2) -> bool:
			return fase.progresso(p) <= aqui + JANELA and not visitados.has(_chave(p))
		)

		if not agora.is_empty():
			for alvo in agora:
				visitados[_chave(alvo)] = true
				await _ir(jogador, alvo, transito)
				# As tarefas da Fase 2 chegam caindo: sem esperar o pouso, o robô passa
				# por onde a tarefa ainda vai estar.
				for i in 4:
					await get_tree().physics_frame
			continue

		if aqui >= fim:
			return

		# Nada por perto: avança um passo e deixa a fase produzir o que vem a seguir.
		await _ir(
			jogador,
			jogador.global_position + fase.eixo_de_avanco().normalized() * PASSO_DE_VARREDURA,
			transito
		)
		if aqui >= fim:
			return


## Identidade de um alvo para a lista de visitados. Arredondada porque uma tarefa que
## oscila não fica duas vezes na mesma coordenada exata.
func _chave(posicao: Vector2) -> Vector2i:
	return Vector2i(posicao / 8.0)


## Onde o robô atento precisa encostar: toda tarefa que vale ponto, mais o ponto de
## DELEGAR de cada bifurcação Q3 — delegar vale +60 contra +40 de resolver sozinho, então
## é o que o teto exige. Distrações (Q4) ficam de fora: para elas, a ação correta é não
## encostar.
func _roteiro(fase: Node2D) -> Array:
	var alvos: Array = []

	for tarefa in fase.get_node("Tarefas").get_children():
		if not ("categoria" in tarefa) or tarefa.esta_resolvida():
			continue
		if tarefa.categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
			continue
		alvos.append(tarefa.global_position)

	for bifurcacao in fase.get_node("Bifurcacoes").get_children():
		var ponto := bifurcacao.get_node_or_null("PontoDelegar")
		if ponto != null:
			alvos.append(ponto.global_position)

	# Na ordem em que o jogador encontraria: projeção no eixo de avanço da fase.
	alvos.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return fase.progresso(a) < fase.progresso(b)
	)
	return alvos


## Teleporta em passos curtos, porque Area2D só detecta em quadro de física — um salto
## direto atravessaria a fase inteira sem disparar nada. `transito` INF significa ir em
## linha reta, sem subir antes.
func _ir(jogador: CharacterBody2D, destino: Vector2, transito: float) -> void:
	if is_inf(transito):
		await _reta(jogador, destino)
		return
	await _reta(jogador, Vector2(jogador.global_position.x, transito))
	await _reta(jogador, Vector2(destino.x, transito))
	await _reta(jogador, destino)


func _reta(jogador: CharacterBody2D, destino: Vector2) -> void:
	var origem := jogador.global_position
	var passos := int(maxf(origem.distance_to(destino) / 10.0, 1.0))
	for i in range(passos + 1):
		jogador.global_position = origem.lerp(destino, float(i) / float(passos))
		jogador.velocity = Vector2.ZERO
		await get_tree().physics_frame


func _fotografar_placar() -> Dictionary:
	return {
		"pontuacao": GameManager.pontuacao_total,
		"tempo_gasto": GameManager.tempo_gasto if not GameManager.em_jogo
			else GameManager.TEMPO_PADRAO_FASE - GameManager.tempo_restante,
		"vitoria": GameManager.ultima_vitoria,
		"por_categoria": GameManager.tarefas_por_categoria.duplicate(),
		"pontos_categoria": GameManager.pontuacao_por_categoria.duplicate(),
		"acoes": GameManager.acoes_por_tipo.duplicate(),
	}


func _abrir(config: Dictionary) -> Node2D:
	var fase: Node2D = load(config["cena"]).instantiate()
	add_child(fase)
	await get_tree().process_frame
	await get_tree().process_frame
	# O perseguidor do Dia 1 tiraria segundos em momentos que dependem de quantos quadros
	# o headless rodou — isso mediria a máquina, não o jogo.
	var prazo := fase.get_node_or_null("Inimigos/Prazo")
	if prazo != null:
		prazo.queue_free()
		await get_tree().process_frame
	return fase


func _fechar(fase: Node2D) -> void:
	get_tree().paused = false
	fase.queue_free()
	await get_tree().process_frame


# Saída

func _escrever() -> void:
	var texto := _cabecalho()
	texto += _tabela_composicao()
	texto += _tabela_perfis()
	texto += _tabela_por_categoria()
	texto += _secao_dia_3()
	texto += _rodape()

	var arquivo := FileAccess.open(DESTINO, FileAccess.WRITE)
	if arquivo == null:
		print("não consegui escrever em ", DESTINO)
		return
	arquivo.store_string(texto)
	arquivo.close()
	print("\nescrito em ", ProjectSettings.globalize_path(DESTINO))


func _cabecalho() -> String:
	return """# Resultados quantitativos — caracterização das fases

> **Gerado automaticamente** por `tools/metricas.gd`
> (`godot --headless --path . res://tools/metricas.tscn`). Não editar à mão: rode de novo.
>
> **Estes números medem o JOGO, não jogadores.** Os dois perfis abaixo são robôs
> determinísticos que delimitam o intervalo de resultados possíveis — o teto de quem trata
> tudo e o piso de quem atravessa sem prestar atenção. **Nenhum número deste documento
> pode ser apresentado como desempenho humano.** O playtest com pessoas é outra coisa, e
> continua pendente.

"""


## O Dia 3 entra por aqui, e não na lista FASES, porque os dois perfis de robô são
## definidos por PERCURSO: eles teleportam de tarefa em tarefa ao longo de um corredor e
## medem quanto se colhe indo devagar contra quanto se colhe correndo reto. A Fase 3 não
## tem corredor — é uma arena de uma tela só, e as demandas chegam ao longo do tempo em
## posições sorteadas.
##
## Rodar os mesmos perfis lá produziria números que pareceriam comparáveis e não seriam.
## O que dá para afirmar sem simular é o que é determinístico: a composição do dia e o
## teto teórico, que saem do orçamento de dificuldade — e é exatamente por esse orçamento
## ser fixo que o ranking da Etapa 7 continua comparando jogadores do Dia 3 entre si.
func _secao_dia_3() -> String:
	var Sorteio := load("res://scripts/sorteio_arena.gd")
	var teto := 0
	var composicao := {}
	for categoria in GameManager.Categoria.values():
		var quantas: int = int(Sorteio.ORCAMENTO.get(categoria, 0))
		composicao[categoria] = quantas
		teto += quantas * int(PONTOS_IDEAIS[categoria])

	var texto := "\n## Dia 3 — \"O Chefe\"\n\n"
	texto += "A fase final não é um corredor: é uma arena em que a Matriz de Eisenhower "
	texto += "é a própria planta da sala, e o jogador carrega cada papel até o canto do "
	texto += "quadrante em que o classificou. O layout é **sorteado a cada partida** — "
	texto += "posição dos quatro cantos, rota até o mezanino, ordem e ponto de queda das "
	texto += "demandas — para que o percurso não possa ser decorado.\n\n"

	texto += "| Q1 | Q2 | Q3 | Q4 | Total | Teto teórico | Expediente |\n"
	texto += "|---|---|---|---|---|---|---|\n"
	texto += "| %d | %d | %d | %d | %d | %d pts | %ds |\n" % [
		composicao[0], composicao[1], composicao[2], composicao[3],
		Sorteio.total_de_demandas(), teto, int(GameManager.SEGUNDOS_DO_DIA[3]),
	]

	texto += "\n**Os dois perfis de robô das tabelas acima não foram executados no Dia 3, "
	texto += "e isso é decisão, não omissão.** Eles são definidos por percurso — colhem ao "
	texto += "longo de um corredor e comparam quem anda devagar com quem corre reto. Numa "
	texto += "arena sem corredor, os mesmos perfis devolveriam números que *pareceriam* "
	texto += "comparáveis aos dos Dias 1 e 2 sem ser. O que este documento afirma sobre o "
	texto += "Dia 3 é só o que é determinístico.\n\n"
	texto += "O que garante que o ranking continue justo apesar do sorteio é o **orçamento "
	texto += "de dificuldade**: a quantidade de tarefas por quadrante, a duração do "
	texto += "expediente e a frequência dos ataques são fixas, e só as *posições* variam. "
	texto += "Isso é conferido por teste em `tests/teste_fase_03.gd` (cenário 1), que "
	texto += "verifica as invariantes em 200 sementes diferentes.\n"
	return texto


func _tabela_composicao() -> String:
	var texto := "## O que cada dia contém\n\n"
	texto += "| Dia | Q1 | Q2 | Q3 | Q4 | Teto teórico | Elevador exige | Expediente | Percurso |\n"
	texto += "|---|---|---|---|---|---|---|---|---|\n"
	for linha in linhas:
		var e: Dictionary = linha["estatica"]
		var c: Dictionary = e["composicao"]
		texto += "| %d | %d | %d | %d | %d | %d pts | %d urgentes | %ds | %d px |\n" % [
			linha["dia"], c[0], c[1], c[2], c[3],
			e["teto"], e["meta"], int(e["expediente"]), int(e["percurso"]),
		]
	texto += "\n*Teto teórico* = somatório do Quadro 1 da Metodologia sobre a composição da "
	texto += "fase: cada Q1 a +100, cada Q2 a +80, cada Q3 delegada a +60. Distrações "
	texto += "valem 0 quando evitadas, que é a ação correta.\n\n"
	return texto


func _tabela_perfis() -> String:
	var texto := "## Os dois perfis\n\n"
	texto += "| Dia | Perfil | Pontuação | % do teto | Tempo de expediente | Concluiu? |\n"
	texto += "|---|---|---|---|---|---|\n"
	for linha in linhas:
		var teto: int = maxi(int(linha["estatica"]["teto"]), 1)
		for chave in ["atento", "apressado"]:
			var r: Dictionary = linha[chave]
			texto += "| %d | %s | %d pts | %d%% | %.1fs | %s |\n" % [
				linha["dia"], chave, r["pontuacao"],
				int(round(100.0 * float(r["pontuacao"]) / float(teto))),
				r["tempo_gasto"], "sim" if r["vitoria"] else "não",
			]
	texto += "\nA distância entre as duas linhas de cada dia é o que o jogo cobra por "
	texto += "prioridade: é ela, e não a velocidade, que separa um placar do outro. O "
	texto += "perfil apressado não conclui nenhum dia — o elevador só abre depois da cota "
	texto += "de urgentes, então correr para a saída é literalmente um beco sem saída: "
	texto += "chegar lá com urgente deixada para trás encerra o expediente em derrota, "
	texto += "porque uma tarefa ultrapassada não volta a ser coletável.\n\n"
	texto += "Duas ressalvas de leitura, para a tabela não dizer mais do que mediu:\n\n"
	texto += "- **O perfil atento não é o ótimo provado**, é um robô guloso. Onde ele fica "
	texto += "abaixo de 100% foi por encostar numa distração de passagem ou por resolver "
	texto += "sozinho uma Q3 em vez de delegar — as duas coisas que ele não sabe planejar. "
	texto += "O teto continua sendo o da coluna anterior.\n"
	texto += "- **A coluna de tempo não é ritmo humano.** O robô se desloca por teleporte, "
	texto += "então ela mede quanto do expediente a ROTA consome, não quanto um jogador "
	texto += "levaria. No perfil apressado ela é ainda menos comparável: o expediente dele "
	texto += "não chega ao fim, é interrompido no elevador.\n\n"
	return texto


## Nota POR CATEGORIA, e não só o agregado: é a leitura que o jogo se propõe a produzir,
## e a que o texto do TCC cita como resultado.
func _tabela_por_categoria() -> String:
	var texto := "## Nota por categoria (perfil atento)\n\n"
	texto += "| Dia | Categoria | Tratadas / existentes | Pontos |\n"
	texto += "|---|---|---|---|\n"
	for linha in linhas:
		var r: Dictionary = linha["atento"]
		var c: Dictionary = linha["estatica"]["composicao"]
		for categoria in [0, 1, 2, 3]:
			texto += "| %d | %s | %d de %d | %+d |\n" % [
				linha["dia"], NOME_CURTO[categoria],
				int(r["por_categoria"][categoria]), int(c[categoria]),
				int(r["pontos_categoria"][categoria]),
			]

	texto += "\n### Ações registradas (perfil atento)\n\n"
	texto += "| Dia | Delegou | Resolveu sozinho | Evitou distração | Colidiu | Deixou passar |\n"
	texto += "|---|---|---|---|---|---|\n"
	for linha in linhas:
		var a: Dictionary = linha["atento"]["acoes"]
		texto += "| %d | %d | %d | %d | %d | %d |\n" % [
			linha["dia"],
			int(a[GameManager.Acao.DELEGAR]), int(a[GameManager.Acao.RESOLVER]),
			int(a[GameManager.Acao.EVITOU]), int(a[GameManager.Acao.COLIDIU]),
			int(a[GameManager.Acao.IGNOROU]),
		]
	texto += "\n"
	return texto


## Os números de cobertura são digitados, não medidos — esta ferramenta não roda as
## suítes, ela caracteriza as fases. Quando um cenário novo entrar, reconte com:
##     grep -c -- "--- cenário" tests/teste_fase_01.gd
##     godot --headless --path . res://tests/teste_fase_01.tscn | grep -cE "^  (ok|FALHA)"
func _rodape() -> String:
	return """## Cobertura dos testes automatizados

Estes números vêm de outra ferramenta — as suítes em `tests/`, que exercitam as fases de
verdade e falham com código de saída 1. Elas são o "procedimento técnico com componente
empírico" da Metodologia.

| Suíte | Cenários | Asserções | O que cobre |
|---|---|---|---|
| `teste_fase_01` | 17 | 171 | pontuação, geometria do pulo integrada, robô que atravessa a pé, estados do urso e a altura que ele persegue, colega, pasta, modo foco, setores anunciados dos dois corredores e a derrota ao chegar ao elevador com urgente perdida |
| `teste_fase_02` | 10 | 91 | agenda determinística por posição, interrupção, geometria das chegadas, maturação de pendências, Q2 fora da linha de corrida, o orçamento de relógio do percurso perfeito e a contagem de urgentes ainda por chegar |
| `teste_fase_03` | 9 | 118 | as invariantes do sorteio em 200 sementes, a recusa de geometria quebrada, as 16 combinações canto x quadrante, a aritmética do soterramento, as fases do Chefe, um robô que pega e entrega um papel a pé, e as quatro mecânicas de pressão do expediente |
| `teste_ranking` | 7 | 45 | payload por quadrante, ordem do ranking, fila offline, ausência de credenciais |
| **total** | **43** | **429** | |

Rodar todas:

```bash
godot --headless --path . res://tests/teste_fase_01.tscn
godot --headless --path . res://tests/teste_fase_02.tscn
godot --headless --path . res://tests/teste_fase_03.tscn
godot --headless --path . res://tests/teste_ranking.tscn
```
"""
