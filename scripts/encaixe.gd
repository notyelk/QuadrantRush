extends RefCounted

## Mantém o conteúdo de um painel dentro dele.
##
## As telas de relatório crescem com a partida — uma linha por quadrante, as extras de
## cada dia, os dez colocados do ranking —, e sem isto a fileira de botões sai por baixo
## da caixa. O conteúdo encolhe em bloco em vez de vazar.


static func no_painel(painel: Control, conteudo: Control, margem := 8.0) -> void:
	conteudo.scale = Vector2.ONE
	var disponivel: float = painel.size.y - margem * 2.0
	var precisa: float = conteudo.get_combined_minimum_size().y
	if disponivel <= 0.0 or precisa <= disponivel:
		return

	# Pivô no topo e no meio: encolher a partir do canto deixaria o painel com um vão
	# embaixo e o título fora do eixo.
	conteudo.pivot_offset = Vector2(conteudo.size.x * 0.5, 0.0)
	var fator: float = clampf(disponivel / precisa, 0.55, 1.0)
	conteudo.scale = Vector2(fator, fator)
