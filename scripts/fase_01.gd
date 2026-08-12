# Herança por caminho, e não pelo class_name FaseBase: nomes globais de classe vivem no
# cache que o EDITOR gera, e este projeto roda teste e captura de tela por linha de
# comando, sem abrir o editor. Pelo caminho funciona nos dois modos.
extends "res://scripts/fase_base.gd"

## Fase 1 — "O primeiro dia" (Etapas 4, 5 e 6 da Metodologia).
##
## Toda a orquestração comum (checkpoints, queda, pausa, relógio, tela de resultado)
## mora em scripts/fase_base.gd. Aqui fica só o que é próprio deste dia.
##
## Estrutura de setores:
##   0 recepção (tutorial) · 1 Q1 · 2 Q2 · 3 Q3 · 4 Q4 · 5 misto · 6 saída
##
## As tarefas estão PARADAS no corredor: o jogador escolhe em que ordem chega nelas.
## É o contrário da Fase 2, em que elas chegam sozinhas — e é por isso que este dia vem
## primeiro. Aqui o elevador exige TODAS as urgentes, o que só é justo porque nenhuma
## delas pode passar despercebida: elas esperam.

## Duração do expediente. Caiu de 90s para 60s junto com o redesenho de escassez: com 90s
## e um percurso mínimo de 17s sobravam mais de 70 segundos, dava para
## fazer a fase inteira duas vezes, e sem escassez a Matriz de Eisenhower não ensina nada
## — ela é uma ferramenta de alocação sob escassez.
##
## 60 é o ALVO de design, não um número medido. O valor final sai da calibragem (rota
## perfeita entre 75% e 80% do relógio), e essa medição só vale depois
## da pasta, que muda a velocidade do jogador e portanto o orçamento inteiro. Medir agora
## seria medir uma fase que ainda vai mudar.
const TEMPO_FASE := 60.0


func tempo_de_expediente() -> float:
	return TEMPO_FASE


func numero_do_dia() -> int:
	return 1


## O Dia 1 é o único que usa a pasta, porque é o único corredor com caixas de saída: quem
## faz tudo sozinho e não entrega nada vai ficando lento, e delegar é a única ação que
## pontua sem pesar.
func usa_pasta() -> bool:
	return true


## O Dia 1 é onde o modo foco nasce. Ele é o antídoto para a queixa de que não dá tempo
## de ler: em foco o enunciado aparece de bem mais longe e a distração não acerta, e o
## preço é ritmo. Nunca é obrigatório — nenhuma travessia da fase exige estar em foco.
func usa_foco() -> bool:
	return true


## Os trechos do corredor, anunciados quando o jogador entra em cada um.
##
## Os setores sempre existiram na geometria, mas sem anúncio o jogador via um corredor
## uniforme. Nomeá-los torna a fase legível pela mesma razão que capítulos tornam um livro
## legível.
##
## As dicas do Dia 1 são instrutivas, e é a única fase em que são: é o dia de ensinar.
## Nenhuma entrega a classificação de uma tarefa — dizem onde as coisas ficam e que troca
## cada trecho propõe, que é o mapa, não o gabarito.
##
## O setor 0 fica de fora de propósito: quem o anuncia é a mensagem de abertura, e duas
## faixas sobrepostas no primeiro segundo não seriam lidas.
func setores() -> Array:
	return [
		{
			"em": 520.0, "nome": "AS BAIAS",
			"dica": "Nem tudo que pisca é problema seu. Segure Shift para ler com calma.",
			"cor": Color("8fd6a8"),
		},
		{
			"em": 1080.0, "nome": "A MESA DO COLEGA",
			"dica": "Subir na bandeja delega; passar por baixo resolve sozinho e custa tempo.",
			"cor": Color("5aa9e6"),
		},
		{
			"em": 1330.0, "nome": "O MEZANINO",
			"dica": "Lá em cima não há distração — e também não há urgência. Ela ficou no chão.",
			"cor": Color("4ea36b"),
		},
		{
			"em": 2180.0, "nome": "O CORREDOR CHEIO",
			"dica": "Trecho de imposto: aqui só há distração. Passe reto ou entre em foco.",
			"cor": Color("f2c14e"),
		},
		{
			"em": 2680.0, "nome": "FIM DO EXPEDIENTE",
			"dica": "O elevador só abre com todas as urgentes resolvidas.",
			"cor": Color("e05c5c"),
		},
	]
