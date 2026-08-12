extends Area2D

## Caixa de saída — onde a pasta se esvazia. Etapa 4 da Metodologia, objetivo ii do TCC.
##
## A pasta acumula peso a cada tarefa feita e nunca entregue, e peso vira lentidão (ver
## GameManager.fator_da_pasta). Esta é a válvula. Encostar zera a carga.
##
## **Não dá ponto nenhum, e isso não é esquecimento.** Os pontos de cada tarefa já foram
## creditados no instante em que ela foi feita — a Etapa 6 exige retorno imediato da
## última tarefa resolvida, e segurar pontuação até a entrega quebraria esse requisito.
## Pagar de novo aqui seria criar uma fonte de pontos fora do Quadro 1 da Metodologia,
## que é o documento já protocolado.
##
## Ela fica numa prateleira fora da linha de corrida, e não no chão. Se estivesse no
## caminho, encostaria sozinha em quem passasse correndo e a decisão sumiria: a mecânica
## inteira é escolher QUANDO parar para entregar, não SE entrega.

const COR := Color("b9c0e0")

@onready var brilho: Sprite2D = $Brilho


func _ready() -> void:
	body_entered.connect(_ao_encostar)
	# O brilho só chama atenção quando há o que entregar. Uma caixa piscando com a pasta
	# vazia mandaria o jogador desviar do caminho para não ganhar nada.
	GameManager.carga_mudou.connect(_ao_mudar_carga)
	_ao_mudar_carga(GameManager.carga_da_pasta)


func _ao_mudar_carga(carga: int) -> void:
	brilho.visible = carga > 0


func _ao_encostar(corpo: Node2D) -> void:
	if not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return
	if GameManager.carga_da_pasta <= 0:
		return

	var entregues := GameManager.entregar_pasta()
	Audio.tocar("comporta")
	Feedback.pontos(get_parent(), global_position + Vector2(0, -10),
		"entregue %d" % entregues, COR)
	Feedback.onda(get_parent(), global_position, COR, 26.0)
	get_tree().call_group(
		"hud", "mostrar_dica", "PASTA VAZIA",
		"%d tarefa(s) entregues — você voltou a andar no ritmo" % entregues, COR, 2)
