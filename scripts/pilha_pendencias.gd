extends RefCounted

## A pilha de pendências da Fase 3: a única forma de PERDER o expediente do Dia 3.
##
## Nos Dias 1 e 2 o relógio é a ameaça: zerou, perdeu. No Dia 3 ele é a esperança —
## sobreviver ao expediente é a vitória, e quem mata é a pilha. Com uma ameaça só, as duas
## não competem pela atenção do jogador, que foi o motivo de o urso sair do Dia 2. E ela é
## escrita por ele: sobe com o que classificou mal, desce com o que classificou bem.
##
## Não pontua nem desconta tempo. Lê contadores que já existem (Acao.IGNOROU, que vale 0)
## e os transforma em altura, por fora de registrar_acao(), para não sujar as notas por
## categoria.
##
## RefCounted e não Node, para que a aritmética seja testável sem cena.

## Quanto cada evento pesa, em unidades.
##
## A Q1 pesa o dobro porque é o único quadrante em que adiar é indefensável: urgente E
## importante não tem para onde ser empurrado. A Q4 pesa ZERO — e isso é a matriz falando:
## se "nem urgente nem importante" fosse a coisa mais perigosa da sala, a fase ensinaria o
## oposto do que o TCC defende.
const PESO_APODRECIDA := {
	GameManager.Categoria.URGENTE_IMPORTANTE: 2,
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: 1,
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: 1,
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: 0,
}

## Papel entregue no canto errado.
##
## Pesa o dobro de uma pendência comum, e mais do que a demanda alivia ao ser acertada
## (-1). A assimetria é o que sustenta a fase: sem ela, largar papel em canto sorteado
## mantém a pilha parada e o expediente se ganha sem classificar nada.
const PESO_ERRO := 2

## Derrota. A altura em pixels é DERIVADA daqui (ver altura_px), e não o contrário: presa
## ao teto da arena, a pilha nunca afoga degraus e mezanino a ponto de tornar a entrega
## impossível.
const SOTERRA := 24

## Limiar de ALERTA: daqui para cima o HUD fica vermelho e a música aperta. É aviso, não
## mudança de geometria — nenhum canto fica inacessível em altura nenhuma da pilha, de
## propósito. A pilha cobra MOBILIDADE (o chão vira perigo), nunca ACESSO.
const ALERTA := 16

## Teto do piche, em pixels. Fica abaixo dos pedestais dos cantos do chão (ver
## sorteio_arena.gd) para que nenhuma entrega deixe de ser possível.
const ALTURA_MAXIMA_PX := 28.0

signal mudou(unidades: int, altura: float)

var unidades: int = 0


## Uma demanda apodreceu sem ser recolhida.
func apodreceu(categoria: int) -> void:
	_somar(int(PESO_APODRECIDA.get(categoria, 1)))


## Uma demanda foi entregue no canto errado.
func errou() -> void:
	_somar(PESO_ERRO)


## Uma demanda foi entregue no canto certo. É a única coisa que faz a pilha BAIXAR, e é
## por isso que a fase é cabo de guerra e não espiral sem saída.
func acertou() -> void:
	_somar(-1)


func _somar(quanto: int) -> void:
	var antes := unidades
	unidades = clampi(unidades + quanto, 0, SOTERRA)
	if unidades != antes:
		mudou.emit(unidades, altura_px())


## Altura da pilha em pixels, a partir do chão. Proporcional, com teto: a regra vive em
## unidades inteiras e a tela é só a leitura dela.
func altura_px() -> float:
	return float(unidades) / float(SOTERRA) * ALTURA_MAXIMA_PX


## Y do topo da pilha no mundo, dado o Y da superfície do chão.
func topo(y_do_chao: float) -> float:
	return y_do_chao - altura_px()


## Já passou do limiar de alerta?
func em_alerta() -> bool:
	return unidades >= ALERTA


## O quanto a fase está perigosa, de 0 a 1 — mesmo contrato que o urso publica em
## `perigo_mudou`, para que música, HUD e câmera reajam sem saber o que é uma pilha.
func perigo() -> float:
	return clampf(float(unidades) / float(SOTERRA), 0.0, 1.0)


## O expediente acabou?
func soterrou() -> bool:
	return unidades >= SOTERRA


func zerar() -> void:
	unidades = 0
	mudou.emit(0, 0.0)
