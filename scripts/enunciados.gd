extends RefCounted

## Sorteia o enunciado de cada tarefa a cada partida.
##
## O que NÃO é sorteado é a posição: em que ponto do corredor cada quadrante aparece é
## geometria validada (a urgente na espinha, a importante fora da linha de corrida, a
## distração no caminho fácil), e embaralhar isso quebraria as travessias. O que muda é o
## TEXTO — quem decorou "servidor caiu, pode pegar" tem de voltar a ler e classificar.
##
## Saca sem repetição enquanto houver estoque no quadrante. As entradas do segundo
## quadrante vêm em par com a crise em que elas se transformam quando adiadas (Dia 2), e
## o par anda junto: separá-los faria a tarefa contar uma história de outra.

const POR_CATEGORIA := {
	GameManager.Categoria.URGENTE_IMPORTANTE: [
		["Cliente ao telefone: o contrato vence hoje"],
		["Servidor de produção fora do ar"],
		["Folha de pagamento fecha em uma hora"],
		["Auditoria pede o relatório ainda hoje"],
		["Nota fiscal do cliente vence em 40 minutos"],
		["Diretoria pede o número do trimestre agora"],
		["Sistema de pagamento caiu no meio da venda"],
		["Entrega combinada para hoje às 18h"],
		["Erro de cobrança atingiu 200 clientes"],
		["Proposta fecha em uma hora e falta assinar"],
		["Banco cobra o boleto que vence hoje"],
		["Falha em produção travou o time inteiro"],
		["Vazamento de dados: responder ao jurídico hoje"],
		["Sistema do cliente fora do ar desde cedo"],
	],
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: [
		["Planejar o roadmap do próximo trimestre",
		 "Diretoria cobra o roadmap na reunião de agora"],
		["Testar o backup antes que ele falhe sozinho",
		 "O backup falhou: recuperar o arquivo do cliente"],
		["Documentar o processo que só você sabe fazer",
		 "Você está de folga amanhã e ninguém sabe rodar o fechamento"],
		["Escrever o manual que ninguém escreveu ainda",
		 "Você entra de férias e ninguém sabe fechar o mês"],
		["Treinar o colega que vai te substituir nas férias",
		 "Você faltou e ninguém no time sabe abrir o sistema"],
		["Revisar a arquitetura antes de escalar",
		 "O sistema caiu no primeiro pico de acesso"],
		["Estudar a nova ferramenta do time",
		 "A migração é hoje e ninguém sabe usar a ferramenta"],
		["Preparar a retrospectiva da sprint",
		 "A reunião começou e não há nada preparado"],
		["Marcar a conversa de carreira com a equipe",
		 "Um bom do time pediu demissão sem aviso"],
		["Revisar o plano de contingência do time",
		 "Faltou energia no prédio e não há plano nenhum"],
		["Organizar o arquivo antes que ele encha",
		 "Ninguém acha o contrato que o cliente está cobrando"],
	],
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: [
		["Reunião de status sem pauta definida"],
		["Pedido de planilha que outro setor já tem pronta"],
		["Ligação de fornecedor para o setor errado"],
		["Formatar o slide que o colega vai apresentar"],
		["Conferir o pedido de material do escritório"],
		["Agendar a sala para a reunião de outro time"],
		["Repassar o comunicado que já foi enviado"],
		["Buscar o dado que já está no relatório aberto"],
	],
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: [
		["Notificação de rede social"],
		["Vídeo engraçado no grupo do trabalho"],
		["Mensagem de voz de dois minutos"],
		["Promoção relâmpago: só nas próximas 2 horas"],
		["Convite para o amigo secreto do setor"],
		["Alguém marcou você numa foto"],
		["Enquete no grupo: pizza ou hambúrguer?"],
		["Newsletter que você nunca assinou"],
		["Corrente de mensagens do grupo da família"],
		["Vídeo de gatinho que alguém encaminhou"],
		["Lista de presentes de fim de ano"],
		["Retrospectiva do ano em vídeo"],
		["Fofoca no corredor"],
		["Colega chamando para o café"],
		["Meme sobre reunião que podia ser e-mail"],
		["Feed de notícias"],
		["Grupo do WhatsApp apitando"],
		["E-mail promocional de loja que você não usa"],
		["Debate no chat sobre o jogo de ontem",],
		["Sorteio de brinde de fornecedor"],
		["Aviso de que a máquina de café voltou"],
		["Thread de vinte respostas com só \"ok\""],
	],
}

## Sacos em uso, por categoria. Estáticos porque o sorteio precisa valer para a fase
## inteira: as tarefas paradas nascem no _ready e as que caem nascem minutos depois, e as
## duas têm de sair do mesmo saco para não repetir enunciado.
static var _sacos := {}


## Reinicia os sacos. Chamado uma vez por expediente, antes de qualquer saque.
static func embaralhar() -> void:
	_sacos = {}
	for categoria in POR_CATEGORIA:
		var saco: Array = POR_CATEGORIA[categoria].duplicate(true)
		saco.shuffle()
		_sacos[categoria] = saco


## Devolve [texto, texto_maduro] do quadrante. O segundo é "" fora do segundo quadrante.
##
## Com o saco vazio ele reembaralha em vez de devolver nada: uma fase com mais tarefas do
## quadrante do que o estoque continua jogável, com repetição, em vez de mostrar papel em
## branco.
static func sacar(categoria: int) -> Array:
	if not _sacos.has(categoria) or (_sacos[categoria] as Array).is_empty():
		var saco: Array = POR_CATEGORIA.get(categoria, [[""]]).duplicate(true)
		saco.shuffle()
		_sacos[categoria] = saco

	var entrada: Array = (_sacos[categoria] as Array).pop_back()
	return [str(entrada[0]), str(entrada[1]) if entrada.size() > 1 else ""]
