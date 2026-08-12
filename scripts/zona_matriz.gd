extends Area2D

## Um dos quatro cantos da sala da Fase 3 — o destino para onde o jogador leva um papel.
##
## O que este nó é, conceitualmente
## Nas Fases 1 e 2 a Matriz de Eisenhower é escrituração invisível: o jogador encosta num
## papel e o jogo decide, nos bastidores, que aquilo era um Q1. Aqui a matriz é a própria
## planta da sala. O canto para onde o jogador CARREGA o papel é a resposta dele sobre em
## que quadrante aquilo está, e o Quadro 1 é aplicado a partir dessa resposta.
##
## O canto não decide nada sozinho: ele avisa a fase que um papel entrou, e a fase resolve.
## É o mesmo contrato de plataforma_tarefa.gd e bifurcacao_q3.gd — quem arbitra é sempre o
## controlador, para que a regra da matriz viva num lugar só.

## Qual quadrante este canto representa. A ordem bate com GameManager.Categoria.
@export_enum(
	"Q1 - Fazer agora",
	"Q2 - Agendar",
	"Q3 - Delegar",
	"Q4 - Lixeira"
) var papel: int = 0

## Emitido quando um papel carregado é entregue aqui.
signal entregue(canto: Node, demanda: Node)

## Nome do canto na placa. Deliberadamente diz a AÇÃO, e não o nome do quadrante: "FAZER
## AGORA" é uma instrução que o jogador consegue casar com um enunciado; "URGENTE E
## IMPORTANTE" seria a resposta da prova impressa na parede.
const ROTULO := {
	GameManager.Categoria.URGENTE_IMPORTANTE: "FAZER AGORA",
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: "AGENDAR",
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: "DELEGAR",
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: "DESCARTAR",
}

@onready var placa: Label = $Placa
@onready var brilho: Polygon2D = $Brilho
## Estrutura do pórtico: recebe a cor do quadrante junto com a placa, para que o canto
## seja reconhecível de longe sem depender de ler o texto.
@onready var pintaveis: Array[Node] = [$Piso, $PosteEsq, $PosteDir, $Travessa]

## O Chefe pode sentar em cima de um canto e desativá-lo por alguns segundos.
var bloqueado := false


func _ready() -> void:
	add_to_group("zona_matriz")
	placa.text = ROTULO[papel]
	# A placa nasce na cor do quadrante porque ela NÃO é a resposta: o jogador precisa
	# saber para onde está indo. O que continua escondido é a categoria do PAPEL, que é o
	# que ele tem de classificar. Colorir o destino ajuda a ler a sala; colorir o papel
	# entregaria a prova, e foi por isso que os ícones deixaram de ser tingidos.
	var cor: Color = GameManager.COR_CATEGORIA[papel]
	placa.add_theme_color_override("font_color", cor)
	brilho.color = Color(cor.r, cor.g, cor.b, 0.1)
	for peca in pintaveis:
		(peca as Polygon2D).color = Color(cor.r, cor.g, cor.b, (peca as Polygon2D).color.a)


## Recebe um papel. Devolve falso se o canto estiver bloqueado, para que quem chamou possa
## avisar o jogador em vez de a entrega sumir em silêncio.
func receber(demanda: Node) -> bool:
	if bloqueado:
		return false
	entregue.emit(self, demanda)
	return true


func bloquear(segundos: float) -> void:
	bloqueado = true
	modulate = Color(0.45, 0.45, 0.5)
	await get_tree().create_timer(segundos).timeout
	bloqueado = false
	modulate = Color.WHITE


## Traduz "que papel era" + "onde foi entregue" na ação do Quadro 1.
##
## Toda saída possível é uma linha da tabela protocolada na seção 3.1 — nenhum ponto novo,
## nenhuma penalidade nova. Se um caso não couber aqui, o problema é o caso.
##
##   Q1 → FAZER AGORA ....... COLETAR   (+100)
##   Q2 → AGENDAR ........... COLETAR   (+80)
##   Q3 → DELEGAR ........... DELEGAR   (+60, sem custo)
##   Q3 → FAZER AGORA ....... RESOLVER  (+40, −5s)   as duas ações que o Quadro 1 prevê
##                                                   para o mesmo quadrante
##   Q4 → DESCARTAR ......... EVITOU    (0)          a Fundamentação chama o quadrante 4
##                                                   de "candidatas à eliminação"
##   Q4 → qualquer outro .... COLIDIU   (−20, −8s)   tratar lixo como trabalho
##   resto .................. IGNOROU   (0)          classificou mal, e a pilha cresce
static func acao_para(categoria: int, canto: int) -> int:
	var C := GameManager.Categoria
	var A := GameManager.Acao

	if categoria == C.NAO_URGENTE_NAO_IMPORTANTE:
		return A.EVITOU if canto == C.NAO_URGENTE_NAO_IMPORTANTE else A.COLIDIU

	if categoria == canto:
		return A.DELEGAR if categoria == C.URGENTE_NAO_IMPORTANTE else A.COLETAR

	# Resolver na hora uma tarefa urgente-mas-não-importante: vale menos e custa tempo,
	# que é literalmente o que o Quadro 1 diz. É a única entrega "fora do canto" que não
	# é erro — é a segunda opção legítima que o quadrante 3 tem.
	if categoria == C.URGENTE_NAO_IMPORTANTE and canto == C.URGENTE_IMPORTANTE:
		return A.RESOLVER

	return A.IGNOROU


## A entrega foi um acerto? Alimenta a pilha: acerto derruba, erro engorda.
static func acertou(categoria: int, canto: int) -> bool:
	var acao := acao_para(categoria, canto)
	return acao in [
		GameManager.Acao.COLETAR,
		GameManager.Acao.DELEGAR,
		GameManager.Acao.RESOLVER,
		GameManager.Acao.EVITOU,
	]
