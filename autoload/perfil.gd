extends Node

## Quem está jogando — e nada além disso. Etapa 6 (campo de nickname na tela de
## título), com a Etapa 7 (Supabase) em vista.
##
## Fica separado do GameManager de propósito. O GameManager é a fonte de verdade de
## PLACAR e TEMPO; identidade é outro assunto. Misturar os dois embaralharia o
## objeto que a tela de resultado lê a cada partida com um dado que atravessa
## partidas. Na Etapa 7 o registro no ranking vai ler os dois lado a lado:
## Perfil.nickname mais os contadores por categoria do GameManager.
##
## Autenticação é nickname sem senha — decisão de escopo já fechada na seção 3.1 da
## Metodologia, não reabrir sem motivo forte.

## Limites do nickname. O mínimo existe para barrar iniciais soltas num ranking
## público; o máximo é o que cabe na linha da tela de resultado, com o viewport de
## 400px de largura.
const MINIMO := 2
const MAXIMO := 16

# Var, e nao const: teste e ferramenta apontam para arquivo descartavel, senao medir
# apagaria o perfil de quem joga nesta maquina.
var caminho := "user://perfil.cfg"

## Quantos dias de expediente já foram liberados. Começa em 1 (só a Fase 1); vencer o
## Dia 1 libera o Dia 2. Mora aqui, e não no GameManager, pela mesma razão do nickname:
## é o que atravessa partidas, enquanto o GameManager zera a cada expediente.
const PRIMEIRO_DIA := 1
## São três expedientes; o terceiro ("O Chefe") é a fase final, e vencer o Dia 2 o libera.
const ULTIMO_DIA := 3

var nickname: String = ""
var dia_liberado: int = PRIMEIRO_DIA


func _ready() -> void:
	carregar()


## Devolve o nickname limpo, ou "" se o texto não servir. Ponto único de validação:
## a tela de título usa isto para decidir se o botão JOGAR fica habilitado, e o
## teste automatizado exercita esta função e não a tela.
func validar(texto: String) -> String:
	var limpo := texto.strip_edges()
	if limpo.length() < MINIMO or limpo.length() > MAXIMO:
		return ""
	return limpo


## Aceita e guarda em memória. Devolve false sem tocar em nada se o texto for
## inválido — quem chama decide o que fazer com a recusa.
func definir(texto: String) -> bool:
	var limpo := validar(texto)
	if limpo.is_empty():
		return false
	nickname = limpo
	return true


## Libera um dia de expediente e devolve true se aquilo foi novidade. Só avança: vencer
## o Dia 1 de novo depois de já ter liberado o Dia 2 não pode trancar nada de volta.
func liberar_dia(numero: int) -> bool:
	var alvo := clampi(numero, PRIMEIRO_DIA, ULTIMO_DIA)
	if alvo <= dia_liberado:
		return false
	dia_liberado = alvo
	salvar()
	return true


func dia_esta_liberado(numero: int) -> bool:
	return numero <= dia_liberado


func salvar() -> void:
	var arquivo := ConfigFile.new()
	arquivo.set_value("jogador", "nickname", nickname)
	arquivo.set_value("jogador", "dia_liberado", dia_liberado)
	arquivo.save(caminho)


## ConfigFile em vez de JSON: é da própria engine, sobrevive ao export WebGL (onde
## user:// vira IndexedDB) e não exige tratar erro de parse na mão.
##
## Qualquer falha de leitura é silenciosa e equivale a "não há perfil": arquivo ausente é
## o caso normal de quem abre o jogo pela primeira vez, e arquivo corrompido não pode
## impedir o jogo de abrir.
func carregar() -> String:
	nickname = ""
	dia_liberado = PRIMEIRO_DIA
	var arquivo := ConfigFile.new()
	if arquivo.load(caminho) != OK:
		return nickname
	nickname = validar(str(arquivo.get_value("jogador", "nickname", "")))
	dia_liberado = clampi(
		int(arquivo.get_value("jogador", "dia_liberado", PRIMEIRO_DIA)),
		PRIMEIRO_DIA, ULTIMO_DIA
	)
	return nickname
