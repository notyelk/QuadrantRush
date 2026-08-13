extends Node2D

## O Chefe da Fase 3 — a fonte de pressão do último expediente.
##
## Não tem vida e não pode ser atingido. O jogador não tem verbo para machucar ninguém —
## a seção 3.1 trava a máquina em Idle/Run/Jump/Fall e as quatro ações do Quadro 1 não são
## ofensivas —, então deixá-lo alcançável criaria a expectativa frustrada de revidar. Ele
## fica num pódio, e o que se vence é o expediente.
##
## Este nó cuida do RITMO: em que fase o expediente está, quando cai a próxima demanda,
## quando começa um ataque. O CONTEÚDO (qual papel, onde, que hazard) é da fase. A
## separação permite testar a progressão sem instanciar hazard nenhum.
##
## Tudo é telegrafado, como o urso do Dia 1: ataque sem aviso não é difícil, é aleatório,
## e puniria quem priorizou certo por não ter adivinhado.

## Quanto dura cada fase do expediente, em segundos.
@export var duracao_da_fase := 25.0

## Intervalo entre demandas, por fase. O aperto do ritmo é a curva de dificuldade inteira.
##
## Calibrado contra o tamanho da fila (38, ver sorteio_arena.gd): 8 + 10 + 11 + 12 = 41
## arremessos cabem nos 100 s, e a fila dura até por volta dos 91 s. Com intervalos mais
## curtos ela seca antes do fim, e a última fase do Chefe fica sem papel para jogar.
@export var intervalos: Array[float] = [3.4, 2.6, 2.2, 2.0]

## Aviso padrão antes de um ataque.
@export var telegrafo := 0.6

## Aviso de ataques que exigem RELER a sala em vez de só desviar. Reorganizar um canto com
## 0,6 s de aviso seria confisco: o jogador não tem como reconstruir a rota nesse tempo, e
## o telegrafo é o que separa dificuldade de injustiça desde o urso do Dia 1.
const TELEGRAFO_LONGO := 1.8

const TELEGRAFO_POR_ATAQUE := {
	"reorganizar": TELEGRAFO_LONGO,
	"enxurrada": 1.2,
}

## Intervalo entre ataques, por fase. 0 = a fase não ataca.
@export var intervalos_de_ataque: Array[float] = [0.0, 7.0, 6.0, 5.0]

## Quanto tempo o Chefe deixa um canto inutilizável quando senta nele.
@export var duracao_do_bloqueio := 6.0

## Que ataques existem em cada fase. Um ataque só aparece na fase que o introduz e nas
## seguintes — a fase 1 é sempre limpa, porque é onde o jogador aprende o laço básico.
##
## "enxurrada" (o e-mail em cópia) NÃO está aqui de propósito: ela tem horário marcado, não
## sorteio. Ver MOMENTOS_DA_ENXURRADA.
const ATAQUES_POR_FASE := [
	[],
	["ligacao"],
	["ligacao", "ocupar", "reorganizar"],
	["ligacao", "ocupar", "reorganizar"],
]

## Em que segundos da ÚLTIMA fase o e-mail em cópia despeja a reserva de Q4.
##
## Horário fixo, e não sorteio, por uma razão de ranking: a reserva de e-mail faz parte do
## orçamento do dia (sorteio_arena.gd), e se ela dependesse de o sorteador escolher
## "enxurrada" o suficiente, dois jogadores do mesmo dia enfrentariam totais diferentes e o
## placar da Etapa 7 deixaria de comparar. Dois bursts, sempre — a reserva sempre é gasta.
const MOMENTOS_DA_ENXURRADA: Array[float] = [4.0, 16.0]

const NOME_DA_FASE := [
	"Bom dia, tudo certo?",
	"Alinhamento rápido",
	"Só um minutinho",
	"Antes de você sair…",
]

signal arremessar()
signal ataque_telegrafado(tipo: String, aviso: float)
signal ataque(tipo: String)
signal fase_mudou(indice: int, nome: String)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var fase_atual := 0
var ativo := false

var _rng := RandomNumberGenerator.new()
var _ate_a_proxima_fase := 0.0
var _ate_a_proxima_demanda := 0.0
var _ate_o_proximo_ataque := 0.0
var _base_y := 0.0
## Quanto já se passou dentro da fase atual — só a última fase usa, para a enxurrada.
var _na_fase := 0.0
var _enxurradas_disparadas := 0


func _ready() -> void:
	add_to_group("chefe")
	_base_y = position.y


## A semente vem da fase, e não daqui, para que a MESMA semente reproduza a arena inteira
## — layout, fila de demandas e ordem dos ataques. Sem isso o teste do robô a pé ficaria
## intermitente, como já aconteceu na suíte da Fase 2.
func comecar(semente: int) -> void:
	_rng.seed = semente
	fase_atual = 0
	ativo = true
	_ate_a_proxima_fase = duracao_da_fase
	_ate_a_proxima_demanda = 1.2      # um respiro antes do primeiro papel
	_ate_o_proximo_ataque = 0.0
	_na_fase = 0.0
	_enxurradas_disparadas = 0
	fase_mudou.emit(0, NOME_DA_FASE[0])


func parar() -> void:
	ativo = false


func _process(delta: float) -> void:
	# Flutua de leve mesmo parado: um chefe imóvel lê como cenário, e ele precisa ler
	# como ameaça mesmo nos segundos em que não está fazendo nada.
	position.y = _base_y + 2.0 * sin(Time.get_ticks_msec() * 0.0022)

	if not ativo or not GameManager.em_jogo:
		return

	_avancar_fase(delta)
	_arremessar(delta)
	_atacar(delta)
	_enxurrar()


func _avancar_fase(delta: float) -> void:
	_na_fase += delta
	if fase_atual >= ATAQUES_POR_FASE.size() - 1:
		return
	_ate_a_proxima_fase -= delta
	if _ate_a_proxima_fase > 0.0:
		return
	fase_atual += 1
	_na_fase = 0.0
	_ate_a_proxima_fase = duracao_da_fase
	_ate_o_proximo_ataque = intervalo_de_ataque() * 0.5
	fase_mudou.emit(fase_atual, NOME_DA_FASE[fase_atual])


## O e-mail em cópia. Só na última fase, em horário marcado, e sempre o mesmo número de
## vezes — é assim que a reserva de Q4 do orçamento sempre acaba sendo gasta.
func _enxurrar() -> void:
	if fase_atual < ATAQUES_POR_FASE.size() - 1:
		return
	if _enxurradas_disparadas >= MOMENTOS_DA_ENXURRADA.size():
		return
	if _na_fase < MOMENTOS_DA_ENXURRADA[_enxurradas_disparadas]:
		return
	_enxurradas_disparadas += 1
	_disparar("enxurrada")


func _arremessar(delta: float) -> void:
	_ate_a_proxima_demanda -= delta
	if _ate_a_proxima_demanda > 0.0:
		return
	_ate_a_proxima_demanda = intervalo_atual()
	sprite.play("jogar")
	arremessar.emit()


func _atacar(delta: float) -> void:
	var intervalo := intervalo_de_ataque()
	if intervalo <= 0.0:
		return
	_ate_o_proximo_ataque -= delta
	if _ate_o_proximo_ataque > 0.0:
		return
	_ate_o_proximo_ataque = intervalo

	var disponiveis: Array = ATAQUES_POR_FASE[fase_atual]
	if disponiveis.is_empty():
		return
	_disparar(disponiveis[_rng.randi_range(0, disponiveis.size() - 1)])


## Telegrafa e, passado o aviso, dispara. Um caminho só para todo ataque, venha ele do
## sorteio ou do horário marcado da enxurrada: dois caminhos divergem assim que alguém
## mexe na guarda de fim de fase.
func _disparar(tipo: String) -> void:
	var aviso: float = TELEGRAFO_POR_ATAQUE.get(tipo, telegrafo)
	ataque_telegrafado.emit(tipo, aviso)
	await get_tree().create_timer(aviso).timeout
	# A fase pode ter acabado durante o telegrafo. Sem esta guarda, um ataque nasceria por
	# cima da tela de resultado — que é o tipo de defeito que só aparece no último segundo.
	if not ativo or not GameManager.em_jogo:
		return
	ataque.emit(tipo)


func intervalo_atual() -> float:
	return intervalos[mini(fase_atual, intervalos.size() - 1)]


func intervalo_de_ataque() -> float:
	return intervalos_de_ataque[mini(fase_atual, intervalos_de_ataque.size() - 1)]


## O quanto o expediente está apertado, de 0 a 1. Usado só para leitura da interface — a
## ameaça de verdade é a pilha, e é ela quem publica `perigo`.
func aperto() -> float:
	return float(fase_atual) / float(maxi(ATAQUES_POR_FASE.size() - 1, 1))
