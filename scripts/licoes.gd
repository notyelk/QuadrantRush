extends RefCounted

## Explicação longa de cada equívoco de classificação, para a tela de lição.
##
## O texto curto que aparece na faixa do HUD durante a partida está em
## GameManager.licao(); aqui fica a versão que o jogador lê com calma depois de perder,
## com o conceito da matriz por trás da decisão.
##
## A chave é o par categoria+ação de GameManager.EQUIVOCOS.

const _POR_CATEGORIA := {
	GameManager.Categoria.URGENTE_IMPORTANTE: {
		GameManager.Acao.IGNOROU: {
			"titulo": "Uma urgente e importante ficou para trás",
			"o_que": "Você passou por essa tarefa sem tratá-la.",
			"certo": "Ela pedia FAZER AGORA — encostar nela assim que apareceu.",
			"porque": (
				"O primeiro quadrante reúne o que tem prazo curto E consequência real. "
				+ "Nada mais na sua mesa compete com isso: adiar não diminui a tarefa, só "
				+ "reduz o tempo que sobra para fazê-la."
			),
			"conceito": (
				"Eisenhower separa urgência (quando vence) de importância (o que acontece "
				+ "se falhar). Quando as duas coincidem, a decisão já está tomada — não há "
				+ "o que priorizar."
			),
			"exemplo": (
				"O contrato que vence hoje. Passar direto por ele não muda o prazo; muda "
				+ "só quem vai explicar por que ele não foi assinado."
			),
		},
	},
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: {
		GameManager.Acao.IGNOROU: {
			"titulo": "Você adiou o que era importante e não urgente",
			"o_que": "Essa tarefa não tinha prazo apertado, e por isso você seguiu em frente.",
			"certo": "Ela pedia um desvio deliberado: parar e resolver enquanto dava.",
			"porque": (
				"É o quadrante que nunca cobra hoje e cobra caro depois. Como nada obriga "
				+ "a fazê-lo, ele só acontece por decisão — e é o único que reduz a "
				+ "quantidade de urgências que você vai enfrentar amanhã."
			),
			"conceito": (
				"Covey chama o segundo quadrante de quadrante da qualidade: viver apagando "
				+ "incêndio no primeiro é, quase sempre, consequência de ter negligenciado o "
				+ "segundo."
			),
			"exemplo": (
				"Testar o backup. Nenhum dia exige isso — até o dia em que o backup falha, "
				+ "e aí a tarefa volta como a crise mais urgente da semana."
			),
		},
	},
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: {
		GameManager.Acao.RESOLVER: {
			"titulo": "Você resolveu sozinho o que dava para delegar",
			"o_que": "A tarefa foi feita, mas com o seu tempo.",
			"certo": "Ela pedia DELEGAR — subir na bandeja e passar adiante.",
			"porque": (
				"Urgente para alguém não é o mesmo que importante para você. Fazer sozinho "
				+ "resolve o problema do outro e gasta o recurso que você não recupera, que é "
				+ "o tempo do seu expediente."
			),
			"conceito": (
				"O terceiro quadrante é o das interrupções: cobra atenção imediata sem "
				+ "contribuir para o seu resultado. A resposta padrão dele é transferir, não "
				+ "executar."
			),
			"exemplo": (
				"A planilha que outro setor usa. Alguém precisa dela hoje; não precisa ser "
				+ "você quem preenche."
			),
		},
		GameManager.Acao.IGNOROU: {
			"titulo": "Uma urgente para os outros ficou sem resposta",
			"o_que": "Você passou reto por uma tarefa que alguém estava esperando.",
			"certo": "Delegar era o melhor caminho; resolver na hora ainda era aceitável.",
			"porque": (
				"O terceiro quadrante não some porque foi ignorado: ele volta, geralmente "
				+ "maior e com mais gente cobrando. Delegar encerra; ignorar só empurra."
			),
			"conceito": (
				"Urgência sem importância pede encaminhamento. A matriz não autoriza "
				+ "descartar esse quadrante — quem se descarta é o quarto."
			),
			"exemplo": (
				"A reunião de status sem pauta. Recusar e mandar um resumo é delegar; não "
				+ "aparecer e não avisar é a mesma reunião marcada de novo amanhã."
			),
		},
	},
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: {
		GameManager.Acao.COLIDIU: {
			"titulo": "Você tratou uma distração como trabalho",
			"o_que": "Encostar nessa tarefa custou pontos e tempo de expediente.",
			"certo": "Ela pedia DESVIAR — passar direto sem se envolver.",
			"porque": (
				"O quarto quadrante não gera resultado nenhum, e mesmo assim consome o "
				+ "mesmo tempo que uma tarefa de verdade. O custo dele não é o que ele "
				+ "entrega: é o que deixou de ser feito enquanto você olhava."
			),
			"conceito": (
				"A Matriz de Eisenhower trata o quarto quadrante como candidato à "
				+ "eliminação. Não é uma tarefa a agendar para depois — é uma tarefa a não "
				+ "fazer."
			),
			"exemplo": (
				"A notificação de rede social no meio do expediente. Ela nunca fica pronta, "
				+ "e cada olhada recomeça a concentração do zero."
			),
		},
	},
}

const _PADRAO := {
	"titulo": "Decisão fora da matriz",
	"o_que": "Essa tarefa não recebeu o tratamento que o quadrante dela pede.",
	"certo": "Releia o enunciado antes de agir.",
	"porque": "Cada quadrante tem uma resposta própria, e trocá-las custa tempo ou pontos.",
	"conceito": "A matriz cruza urgência e importância para definir o que fazer com cada tarefa.",
	"exemplo": "",
}


static func para(categoria: int, acao: int) -> Dictionary:
	var do_quadrante: Dictionary = _POR_CATEGORIA.get(categoria, {})
	return do_quadrante.get(acao, _PADRAO)
