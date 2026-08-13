"""Gera scenes/level/fase_02.tscn a partir do layout descrito aqui embaixo.

Por que um gerador e nao editar a cena a mao: sao 176 colunas, ~1300 celulas pintadas e
duas duzias de colisores. Editar isso no .tscn e inviavel, e escolher coordenada de atlas
no escuro ja produziu tile quebrado duas vezes neste projeto.

Como a Fase 1, este gerador VALIDA antes de escrever e recusa a cena se a geometria for
impossivel ou se ela quebrar uma promessa do design. Cada regra nasceu de um defeito real
-- o defeito esta no comentario dela.

    python tools/gerar_fase_02.py

Confira o resultado com os olhos antes de dar por pronto:
    godot --path . res://tools/screenshot.tscn -- fase_02

Vocabulario de tile:
    source 5  Little_Bits_Office_Floors  piso e topo de plataforma
    source 6  Little_Bits_office_objects moveis soltos
    source 7  Little_Bits_office_walls   parede, rodape e janelas
"""

from __future__ import annotations

import base64
import os
import struct

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "scenes", "level", "fase_02.tscn")

T = 16                      # lado do tile
COLUNAS = 176               # 2816px
LARGURA = COLUNAS * T
ALTURA = 208

LINHA_PISO = 11             # topo do piso em y=176
LINHA_RODAPE = 10
LINHA_TETO = 0

# Fisica do jogador, copiada de scenes/player/player.gd. E duplicacao de proposito: o
# validador precisa da conta ANTES de o Godot abrir, e um teste confere as duas contra a
# fase de verdade depois.
VELOCIDADE_PULO = 350.0
GRAVIDADE = 980.0
VELOCIDADE_MAX = 180.0
ALTURA_PULO = VELOCIDADE_PULO ** 2 / (2 * GRAVIDADE)     # 62.5px

# Faixa de parede em que as janelas ficam (linhas 3 a 7 => y 48..128).
JANELA_LINHA0 = 3
JANELA_LINHAS = 5
JANELA_COLS = 4

# Onde, DENTRO do bloco de janela, o vidro e transparente de verdade. Abrir o bloco
# inteiro deixava a cidade do parallax aparecendo como um retangulo verde em volta do
# caixilho -- foi o print que pegou isso, nao o teste.
VIDRO_COL = 1
VIDRO_LARGURA = 2
VIDRO_LINHA = 5
VIDRO_ALTURA = 1

# layout

# (col_inicio, col_fim_exclusivo) de chao continuo. Os buracos entre eles sao os vaos.
CHAOS = [(0, 88), (91, 108), (112, 176)]

# (col_inicio, col_fim_exclusivo, linha_do_topo). Linha 9 => y=144, 7 => y=112, 5 => y=80.
PLATAFORMAS = [
    (24, 28, 9),    # PA     setor 1
    (32, 36, 7),    # PB     setor 1, degrau alto -- Q2 #1
    (41, 45, 9),    # PC     setor 1
    (52, 56, 9),    # Step1  setor 2
    (57, 62, 7),    # Mez1   setor 2, rota de delegar da Q3a
    (66, 70, 9),    # Step2  setor 2
    (71, 76, 7),    # Mez2   setor 2, rota de delegar da Q3b
    (82, 86, 9),    # PE     setor 3, antes do primeiro vao
    (92, 96, 9),    # PF     setor 3, depois do primeiro vao
    (100, 104, 7),  # PG     setor 3 -- Q2 #2
    (110, 114, 9),  # PH     setor 3, por cima do segundo vao
    (121, 126, 5),  # PK     setor 4, o alto do arquivo -- Q2 #3 (so com a escada)
    (130, 134, 9),  # PL     setor 4
    (139, 143, 9),  # PM     setor 4
    (148, 152, 7),  # PN     setor 5 -- Q2 #4
    (158, 162, 9),  # PO     setor 5
]

# As duas estruturas que so existem depois de delegar. Nascem SEM colisao e quase
# transparentes; o colega despachado as materializa (ver scripts/alvo_delegado.gd).
PONTE = (88, 91, 11)          # tapa o primeiro vao, na altura do piso
ESCADA = (117, 121, 8)        # degrau de acesso ao alto do arquivo (y=128)

# Coluna inicial de cada bloco de janela (4 colunas de largura). Nenhuma pode cair sobre
# uma plataforma das linhas 5 ou 7, senao a plataforma corta a janela ao meio -- bug que
# ja aconteceu duas vezes neste projeto e por isso virou regra do validador.
JANELAS = [4, 12, 20, 46, 64, 78, 88, 94, 106, 135, 143, 154, 168]

# Moveis, por TIPO e nao por celula solta.
#
# tipo -> (largura_em_colunas, linha_do_topo, [[atlas da linha de cima], [da de baixo]])
TIPOS_DE_MOVEL = {
    "mesa":       (2, 9, [[(4, 0), (5, 0)], [(4, 1), (5, 1)]]),
    "armario":    (1, 9, [[(1, 4)], [(1, 5)]]),
    "planta":     (1, 9, [[(3, 4)], [(3, 5)]]),
    "bebedouro":  (1, 9, [[(4, 4)], [(4, 5)]]),
    "cadeira":    (1, 10, [[(1, 2)]]),
    "lixeira":    (1, 10, [[(3, 3)]]),
}

MOVEIS = [
    (6, "mesa"), (10, "cadeira"), (16, "mesa"), (30, "armario"), (38, "planta"),
    (48, "lixeira"), (60, "bebedouro"), (74, "mesa"), (86, "planta"), (98, "cadeira"),
    (116, "armario"), (128, "mesa"), (136, "lixeira"), (146, "bebedouro"),
    (165, "mesa"), (172, "planta"),
]

INICIO_JOGADOR = (48, 160)
SAIDA = (2760, 176)

CHECKPOINTS = [400, 900, 1300, 1800, 2300, 2600]

# (x, texto) das bifurcacoes Q3 -- centradas sob os mezaninos, que sao a rota de delegar.
BIFURCACOES = [
    (952, "Reunião de status sem pauta definida"),
    (1176, "Pedido de planilha que outro setor já tem pronta"),
]

# O colega caminha a 140px/s e o jogador corre a 180. Com ~1s de dianteira, o colega
# chega ao alvo antes do jogador quando a distancia e menor que
# 1 * 140 * 180 / (180 - 140) = 630px. "perto" SEMPRE compensa; "longe" so compensa para
# quem se desviou do caminho reto. Os dois tipos existem de proposito.
VELOCIDADE_COLEGA = 140.0
DIANTEIRA_COLEGA = 1.0

COLEGAS = [
    {
        "bifurcacao": 0, "x": 962, "y": 112, "nome": "PonteDoVao",
        "alvo_x": 1400, "tipo": "perto", "corpo": "Ponte", "visual": "PonteTiles",
        "mensagem": "O colega estendeu a passarela sobre o vão",
    },
    {
        "bifurcacao": 1, "x": 1186, "y": 112, "nome": "EscadaDoArquivo",
        "alvo_x": 1904, "tipo": "longe", "corpo": "Escada", "visual": "EscadaTiles",
        "mensagem": "O colega baixou a escada do arquivo",
    },
]

LADROES = [(1030, 132, 44), (1450, 128, 56)]  # x, y, alcance para cada lado

# Tarefas PARADAS do setor 4 (o arquivo). Nada CAI neste setor, de proposito: depois do
# enxame, o silencio e sentido como recompensa, e e la que ficam as tarefas que exigem
# escalada. (x, y, categoria, texto, texto_maduro)
TAREFAS_FIXAS = [
    (2032, 160, 0, "Diretoria pede o número do trimestre agora", ""),
    (1976, 64, 1, "Escrever o manual que ninguém escreveu ainda",
     "Você entra de férias e ninguém sabe fechar o mês"),
    (2320, 160, 0, "Sistema de pagamento caiu no meio da venda", ""),
]

# a agenda do dia
#
# `x` e onde a coisa vai parar; `pousa` e a altura em que a queda termina. O gatilho e
# derivado em fase_02.gd, nunca digitado aqui.
#
# Regra de ouro desta fase, conferida pelo validador: NENHUMA Q2 pousa na linha de quem
# so corre. Se desse para pegar uma Q2 sem desviar, ninguem adiaria nenhuma e a
# maturacao -- a mecanica central do dia -- nunca apareceria.
AGENDA = [
    # setor 0 · recepcao -- a primeira tarefa cai sem nenhuma ameaca em volta
    (336, 160, 0, "Cliente ao telefone: o contrato vence hoje", "", None),
    (464, 160, 3, "Notificação de rede social", "", (0, 12)),

    # setor 1 · caixa de entrada -- a primeira interrupcao do dia, e a mais barata
    (544, 96, 1, "Planejar o roadmap do próximo trimestre",
     "Diretoria cobra o roadmap na reunião de agora", None),
    (640, 160, 0, "Servidor de produção fora do ar", "", None),
    (656, 66, -1, "", "", None),                      # interrupcao
    (736, 160, 3, "Vídeo engraçado no grupo do trabalho", "", (14, 0)),

    # setor 2 · telefones (as duas bifurcacoes Q3 ficam paradas na cena)
    (800, 160, 3, "Mensagem de voz de dois minutos", "", (0, 13)),
    (976, 160, 0, "Folha de pagamento fecha em uma hora", "", None),
    (1024, 160, 3, "Promoção relâmpago: só nas próximas 2 horas", "", (0, 12)),
    (1120, 72, -1, "", "", None),                     # interrupcao
    (1152, 160, 3, "Convite para o amigo secreto do setor", "", (15, 0)),

    # setor 3 · enxame -- o ritmo dobra e as interrupcoes ficam caras
    (1264, 160, 0, "Auditoria pede o relatório ainda hoje", "", None),
    (1296, 160, 3, "Alguém marcou você numa foto", "", (16, 0)),
    (1360, 70, -1, "", "", None),                     # interrupcao
    (1520, 58, -1, "", "", None),                     # interrupcao
    (1552, 160, 3, "Enquete no grupo: pizza ou hambúrguer?", "", (0, 14)),
    (1600, 160, 0, "Nota fiscal do cliente vence em 40 minutos", "", None),
    (1632, 96, 1, "Testar o backup antes que ele falhe sozinho",
     "O backup falhou: recuperar o arquivo do cliente", None),
    (1696, 160, 3, "Newsletter que você nunca assinou", "", (0, 12)),
    (1760, 60, -1, "", "", None),                     # interrupcao

    # setor 4 · arquivo -- silencio total (so as TAREFAS_FIXAS)

    # setor 5 · fechamento -- as duas ultimas interrupcoes sao as mais rapidas e as
    # mais caras: e o fim do dia, e e quando a atencao ja esta gasta
    (2400, 96, 1, "Documentar o processo que só você sabe fazer",
     "Você está de folga amanhã e ninguém sabe rodar o fechamento", None),
    (2432, 160, 3, "Corrente de mensagens do grupo da família", "", (0, 12)),
    (2480, 64, -1, "", "", None),                     # interrupcao
    (2496, 160, 3, "Vídeo de gatinho que alguém encaminhou", "", (16, 0)),
    (2608, 160, 3, "Lista de presentes de fim de ano", "", (0, 11)),
    (2640, 68, -1, "", "", None),                     # interrupcao
    (2672, 160, 3, "Retrospectiva do ano em vídeo", "", (13, 0)),
]

# Onde uma pendencia amadurecida pode nascer. Sempre no TOPO de uma plataforma da linha 9
# (pousa em y=128), nunca no chao: buscar a crise tem de custar um desvio deliberado, que
# e onde mora o preco de ter adiado.
PONTOS_DE_CRISE = [416, 688, 864, 1088, 1344, 1504, 1792, 2112, 2256, 2560]
CRISE_POUSA = 128

# ferramentas


def celulas_para_dados(celulas: list[tuple[int, int, int, int, int, int]]) -> str:
    """(col, linha, source, atlas_x, atlas_y, alternativa) -> base64 do PackedByteArray."""
    bruto = b"\x00\x00" + b"".join(struct.pack("<6h", *c) for c in celulas)
    return base64.b64encode(bruto).decode()


def par_do_piso(col: int, linha_topo: bool) -> tuple[int, int]:
    """O piso alterna dois tiles para nao virar textura repetida obvia."""
    if linha_topo:
        return (3, 1) if col % 2 == 0 else (4, 1)
    return (3, 2) if col % 2 == 0 else (4, 2)


def colunas_com_chao() -> set[int]:
    cols: set[int] = set()
    for inicio, fim in CHAOS:
        cols.update(range(inicio, fim))
    return cols


def alcance(subida: float, velocidade: float = VELOCIDADE_MAX) -> float:
    """Quanto o jogador anda na horizontal num pulo que precisa subir `subida` px.

    Integra a trajetoria em vez de usar a formula fechada porque a gravidade do Godot e
    aplicada em passos discretos: a formula continua otimista em alguns pixels, e otimismo
    aqui vira travessia impossivel no jogo.
    """
    if subida > ALTURA_PULO:
        return -1.0
    passo = 1.0 / 60.0
    vy = -VELOCIDADE_PULO
    y = 0.0
    t = 0.0
    while True:
        vy += GRAVIDADE * passo
        y += vy * passo
        t += passo
        if vy > 0.0 and -y <= subida:
            break
        if t > 3.0:
            break
    return velocidade * t


def topo_do_corpo(y_do_chao: float) -> float:
    """Altura maxima que o CORPO do jogador alcanca pulando de um piso em `y_do_chao`.

    A origem dele fica 16px acima do piso e a capsula comeca 2px acima da origem.
    """
    return y_do_chao - 16.0 - ALTURA_PULO - 2.0


# validacao


def validar() -> None:
    problemas: list[str] = []
    com_chao = colunas_com_chao()

    # 1. Todo vao tem que caber num pulo. Um vao maior que o alcance real trancaria a
    #    fase, e nenhum teste de LOGICA veria isso -- so um humano caindo.
    for (_i0, f0), (i1, _f1) in zip(CHAOS, CHAOS[1:]):
        largura = (i1 - f0) * T
        # Um vao pode ser coberto por uma plataforma por cima; nesse caso ele nao precisa
        # ser pulado de uma vez.
        coberto = any(
            linha < LINHA_PISO and set(range(inicio, fim)) & set(range(f0, i1))
            for inicio, fim, linha in PLATAFORMAS
        )
        if not coberto and largura > alcance(0.0):
            problemas.append(
                "o vao das colunas %d-%d tem %dpx e o pulo so cobre %.0fpx"
                % (f0, i1, largura, alcance(0.0)))

    # 2. Nenhuma plataforma corta uma janela.
    linhas_janela = set(range(JANELA_LINHA0, JANELA_LINHA0 + JANELA_LINHAS))
    for base in JANELAS:
        cols_janela = set(range(base, base + JANELA_COLS))
        for inicio, fim, linha in PLATAFORMAS + [PONTE, ESCADA]:
            if linha in linhas_janela and cols_janela & set(range(inicio, fim)):
                problemas.append(
                    "janela na coluna %d e cortada pela plataforma %d-%d (linha %d)"
                    % (base, inicio, fim, linha))

    # 3. A REGRA DA FASE: nenhuma Q1 ou Q2 pode ser colhida por quem so corre reto.
    #
    #    Quem corre no piso tem o corpo entre y=158 e y=176, e a tarefa tem raio de
    #    contato 8. Uma Q2 que pousasse ai seria coletada de passagem -- e sem Q2 adiada
    #    nao existe maturacao, que e a mecanica inteira deste dia.
    #
    #    Q1 e a espinha e PODE estar no chao: ela e obrigatoria, e o desenho quer que
    #    ela esteja no caminho. A regra vale para Q2.
    corpo_correndo = (LINHA_PISO * T - 16.0 - 2.0, LINHA_PISO * T)
    for x, pousa, cat, texto, _maduro, _amp in AGENDA:
        if cat == 1 and pousa + 8.0 >= corpo_correndo[0]:
            problemas.append(
                "a Q2 de x=%d pousa em y=%d, dentro da linha de quem so corre (%.0f)"
                % (x, pousa, corpo_correndo[0]))
    for x, y, cat, texto, _maduro in TAREFAS_FIXAS:
        if cat == 1 and y + 8.0 >= corpo_correndo[0]:
            problemas.append(
                "a Q2 fixa de x=%d (y=%d) esta na linha de quem so corre" % (x, y))

    # 3b. E toda Q2 precisa ter enunciado de crise escrito. Sem ele a tarefa nao amadurece
    #     e a mecanica do dia fica silenciosamente menor -- exatamente o tipo de perda que
    #     ninguem nota olhando o jogo rodar.
    for x, _pousa, cat, _texto, maduro, _amp in AGENDA:
        if cat == 1 and not maduro:
            problemas.append("a Q2 de x=%d nao tem texto_maduro: ela nao amadurece" % x)
    for x, _y, cat, _texto, maduro in TAREFAS_FIXAS:
        if cat == 1 and not maduro:
            problemas.append("a Q2 fixa de x=%d nao tem texto_maduro" % x)

    # 4. Toda tarefa que CAI tem que pousar sobre chao ou plataforma de verdade, e nenhuma
    #    pode pousar dentro de um colisor. Duas chegadas ja nasceram enterradas na base de
    #    uma plataforma na versao anterior desta fase.
    topos = {}
    for inicio, fim, linha in PLATAFORMAS:
        for col in range(inicio, fim):
            topos.setdefault(col, []).append(linha * T)
    for x, pousa, cat, _texto, _maduro, _amp in AGENDA:
        if cat < 0:
            continue
        col = x // T
        esperado = pousa + 16
        if esperado == LINHA_PISO * T:
            if col not in com_chao:
                problemas.append("a tarefa de x=%d pousa no chao, mas ali e vao" % x)
            # E o chao nao pode ter uma plataforma da linha 9 por cima: o colisor dela
            # termina exatamente em y=160, que e onde a tarefa pousaria, e ela nasceria
            # encostada nele. Ja aconteceu na versao anterior desta fase, em duas
            # chegadas, e so o teste de geometria viu.
            for inicio, fim, linha in PLATAFORMAS:
                if linha == 9 and inicio <= col < fim:
                    problemas.append(
                        "a tarefa de x=%d pousa no chao sob a plataforma %d-%d da linha 9"
                        % (x, inicio, fim))
        elif esperado not in topos.get(col, []):
            problemas.append(
                "a tarefa de x=%d pousa em y=%d, e nao ha plataforma com topo em y=%d "
                "na coluna %d" % (x, pousa, esperado, col))

    # 5. Os pontos de crise: todos sobre plataforma da linha 9, e espalhados.
    for x in PONTOS_DE_CRISE:
        col = x // T
        if CRISE_POUSA + 16 not in topos.get(col, []):
            problemas.append(
                "o ponto de crise x=%d nao cai sobre uma plataforma de topo y=%d"
                % (x, CRISE_POUSA + 16))
    for a, b in zip(PONTOS_DE_CRISE, PONTOS_DE_CRISE[1:]):
        if b <= a:
            problemas.append("PONTOS_DE_CRISE fora de ordem em x=%d" % b)
    #    O primeiro ponto tem que aparecer cedo: a primeira Q2 e em x=544 e a crise dela
    #    nasce "a frente". Sem ponto disponivel logo depois, a maturacao -- que e a
    #    mecanica do dia -- so apareceria tarde demais para ensinar alguma coisa.
    if PONTOS_DE_CRISE[0] > 800:
        problemas.append("o primeiro ponto de crise (x=%d) esta tarde demais"
                         % PONTOS_DE_CRISE[0])

    # 6. A conta dos 630px do colega (mesma regra da Fase 1). Mover uma bandeja
    #    transformaria delegar em decoracao sem quebrar nada visivel.
    limite = DIANTEIRA_COLEGA * VELOCIDADE_COLEGA * VELOCIDADE_MAX / (
        VELOCIDADE_MAX - VELOCIDADE_COLEGA)
    for c in COLEGAS:
        x_bandeja = BIFURCACOES[c["bifurcacao"]][0]
        d = abs(c["alvo_x"] - x_bandeja)
        real = "perto" if d < limite else "longe"
        if real != c["tipo"]:
            problemas.append(
                "%s: alvo a %.0fpx da bandeja e '%s' (limite %.0fpx), mas o design pede "
                "'%s'" % (c["nome"], d, real, limite, c["tipo"]))
        # E o colega tem de nascer DENTRO do gatilho de delegar (36x44 centrado 10px
        # abaixo do PontoDelegar, que fica 74px acima da bifurcacao). Foi o defeito achado
        # jogando: "vejo o colega, passo nele e nao acontece nada".
        if abs(c["x"] - x_bandeja) > 18 - 4:
            problemas.append(
                "%s nasce a %dpx da bandeja: fora do gatilho de delegar"
                % (c["nome"], abs(c["x"] - x_bandeja)))
        centro_gatilho = LINHA_PISO * T - 74 + 10
        if abs(c["y"] - centro_gatilho) > 22 - 4:
            problemas.append(
                "%s nasce em y=%d, fora da altura do gatilho (centro %d)"
                % (c["nome"], c["y"], centro_gatilho))
        # E ele tem de POUSAR no topo da bandeja: dentro dela, aparece enterrado.
        topos = [linha * T for i, f, linha in PLATAFORMAS
                 if i * T <= c["x"] <= f * T]
        if c["y"] not in topos:
            problemas.append(
                "%s nasce em y=%d, que nao e o topo de nenhuma plataforma sob ele (%s)"
                % (c["nome"], c["y"], topos))

    # 7. A Q2 do alto do arquivo tem de ser INALCANCAVEL sem a escada delegada -- e o que
    #    garante que nao existe pontuacao maxima sem delegar. Sem esta conta a promessa
    #    seria so uma posicao bonita.
    q2_alta = [(x, y) for x, y, cat, *_ in TAREFAS_FIXAS if cat == 1 and y < 96]
    if not q2_alta:
        problemas.append("nenhuma Q2 no alto do arquivo: delegar deixa de ser exigido")
    for x, y in q2_alta:
        col = x // T
        for inicio, fim, linha in PLATAFORMAS:
            if linha * T >= LINHA_PISO * T:
                continue
            # De que plataformas da-se para alcanca-la?
            dx = 0
            if col < inicio:
                dx = (inicio - col) * T
            elif col >= fim:
                dx = (col - fim + 1) * T
            if inicio <= col < fim and linha * T - 16 == y:
                continue                         # e a propria prateleira dela
            subida = (linha * T) - y - 8
            if subida <= ALTURA_PULO and dx <= alcance(max(subida, 0.0)):
                if (inicio, fim, linha) != tuple(ESCADA):
                    problemas.append(
                        "a Q2 de x=%d (y=%d) e alcancavel da plataforma %d-%d (linha %d) "
                        "sem a escada delegada" % (x, y, inicio, fim, linha))
        if topo_do_corpo(LINHA_PISO * T) <= y + 8:
            problemas.append(
                "a Q2 de x=%d (y=%d) e alcancavel do proprio chao" % (x, y))

    # 8. Nenhum movel flutua sobre um vao, e nenhum invade plataforma da linha 9.
    ocupadas = set()
    for inicio, fim, linha in PLATAFORMAS:
        if linha == 9:
            ocupadas.update(range(inicio, fim))
    for col, tipo in MOVEIS:
        largura = TIPOS_DE_MOVEL[tipo][0]
        for dc in range(largura):
            if col + dc in ocupadas:
                problemas.append("movel '%s' na coluna %d invade uma plataforma"
                                 % (tipo, col + dc))
            if col + dc not in com_chao:
                problemas.append("movel '%s' na coluna %d flutua sobre o vao"
                                 % (tipo, col + dc))

    # 9. As estruturas delegaveis nao podem estar no caminho obrigatorio. A ponte tapa um
    #    vao que ja e pulavel e a escada leva a um bonus -- nenhuma das duas pode ser
    #    necessaria para terminar o dia, senao quem resolver a Q3 em vez de delegar ficaria
    #    preso, e resolver e uma resposta legitima do Quadro 1.
    for nome, estrutura in [("Ponte", PONTE), ("Escada", ESCADA)]:
        inicio, fim, linha = estrutura
        if nome == "Ponte":
            largura = (fim - inicio) * T
            if largura > alcance(0.0):
                problemas.append(
                    "sem a ponte o vao de %dpx fica impossivel: delegar viraria "
                    "obrigatorio" % largura)

    if problemas:
        print("VALIDACAO FALHOU:")
        for p in problemas:
            print("  - " + p)
        raise SystemExit(1)

    print("validacao ok: %d plataformas, %d janelas, %d chegadas, %d pontos de crise"
          % (len(PLATAFORMAS), len(JANELAS),
             len([e for e in AGENDA if e[2] >= 0]), len(PONTOS_DE_CRISE)))


# camadas


def camada_piso() -> list:
    celulas = []
    for inicio, fim in CHAOS:
        for col in range(inicio, fim):
            celulas.append((col, LINHA_PISO, 5) + par_do_piso(col, True) + (0,))
            celulas.append((col, LINHA_PISO + 1, 5) + par_do_piso(col, False) + (0,))
    for inicio, fim, linha in PLATAFORMAS:
        for col in range(inicio, fim):
            celulas.append((col, linha, 5) + par_do_piso(col, True) + (0,))
    return celulas


def camada_de(estrutura: tuple[int, int, int]) -> list:
    inicio, fim, linha = estrutura
    return [(col, linha, 5) + par_do_piso(col, True) + (0,) for col in range(inicio, fim)]


def camada_decoracao() -> list:
    celulas = []
    # Teto e rodape correm o nivel inteiro: sao o que faz o corredor parecer um corredor.
    for col in range(COLUNAS):
        celulas.append((col, LINHA_TETO, 7, 3, 6, 0))
        celulas.append((col, LINHA_RODAPE, 7, 3, 6, 0))
    for base in JANELAS:
        for dx in range(JANELA_COLS):
            for dy in range(JANELA_LINHAS):
                celulas.append((base + dx, JANELA_LINHA0 + dy, 7, 1 + dx, dy, 0))
    return celulas


def camada_objetos() -> list:
    celulas = []
    for col, tipo in MOVEIS:
        largura, linha0, grade = TIPOS_DE_MOVEL[tipo]
        for dl, fileira in enumerate(grade):
            for dc, (ax, ay) in enumerate(fileira):
                celulas.append((col + dc, linha0 + dl, 6, ax, ay, 0))
    return celulas


def vaos_de_parede() -> list[tuple[int, int]]:
    """Trechos (x0, x1) da faixa do vidro que continuam sendo parede fechada.

    Derivado das colunas de janela, nunca digitado a mao: e assim que se garante que a
    cidade do parallax aparece exatamente atras do vidro e em nenhum outro lugar.
    """
    aberto = set()
    for base in JANELAS:
        aberto.update(range(base + VIDRO_COL, base + VIDRO_COL + VIDRO_LARGURA))

    trechos = []
    inicio = None
    for col in range(COLUNAS + 1):
        fechado = col < COLUNAS and col not in aberto
        if fechado and inicio is None:
            inicio = col
        elif not fechado and inicio is not None:
            trechos.append((inicio * T, col * T))
            inicio = None
    return trechos


# montagem


def retangulo(nome: str, largura: int, altura: int) -> str:
    return '[sub_resource type="RectangleShape2D" id="%s"]\nsize = Vector2(%d, %d)\n\n' % (
        nome, largura, altura,
    )


def escapar(texto: str) -> str:
    return texto.replace('"', '\\"')


def main() -> None:
    validar()

    piso = celulas_para_dados(camada_piso())
    decoracao = celulas_para_dados(camada_decoracao())
    objetos = celulas_para_dados(camada_objetos())
    ponte_tiles = celulas_para_dados(camada_de(PONTE))
    escada_tiles = celulas_para_dados(camada_de(ESCADA))

    formas: dict[tuple[int, int], str] = {}

    def forma(largura: int, altura: int) -> str:
        chave = (largura, altura)
        if chave not in formas:
            formas[chave] = "Shape_%dx%d" % (largura, altura)
        return formas[chave]

    colisores = []
    for i, (inicio, fim) in enumerate(CHAOS):
        largura = (fim - inicio) * T
        cx = inicio * T + largura // 2
        colisores.append(("Chao%d" % i, cx, 192, forma(largura, 32), True))
    for i, (inicio, fim, linha) in enumerate(PLATAFORMAS):
        largura = (fim - inicio) * T
        cx = inicio * T + largura // 2
        colisores.append(("Plataforma%d" % i, cx, linha * T + 8, forma(largura, 16), True))
    # As duas delegaveis nascem DESLIGADAS: o colega e quem liga a colisao.
    for nome, (inicio, fim, linha) in [("Ponte", PONTE), ("Escada", ESCADA)]:
        largura = (fim - inicio) * T
        cx = inicio * T + largura // 2
        colisores.append((nome, cx, linha * T + 8, forma(largura, 16), False))

    # Fecha as duas pontas do corredor: a camera tem limite, o corpo do jogador nao.
    for nome, cx in [("BordaEsquerda", -8), ("BordaDireita", LARGURA + 8)]:
        colisores.append((nome, cx, ALTURA // 2, forma(16, ALTURA * 3), True))

    forma_checkpoint = forma(8, 56)
    forma_queda = forma(LARGURA, 60)

    p = []
    a = p.append
    a("[gd_scene load_steps=%d format=3]\n\n" % 0)  # corrigido no fim

    a('[ext_resource type="Script" path="res://scripts/fase_02.gd" id="script_fase"]\n')
    a('[ext_resource type="Script" path="res://scripts/spawner_tarefas.gd" id="script_spawner"]\n')
    a('[ext_resource type="Script" path="res://scripts/alvo_delegado.gd" id="script_alvo"]\n')
    a('[ext_resource type="TileSet" path="res://scenes/tiles/escritorio.tres" id="tileset"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/level/camera.tscn" id="cena_camera"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="cena_player"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/tarefa.tscn" id="cena_tarefa"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/bifurcacao_q3.tscn" id="cena_q3"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/saida.tscn" id="cena_saida"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/ladrao_de_tempo.tscn" id="cena_ladrao"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/colega.tscn" id="cena_colega"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="cena_hud"]\n')
    a('[ext_resource type="Texture2D" path="res://sprites/Parallax Industrial/bg.png" id="px_bg"]\n')
    a('[ext_resource type="Texture2D" path="res://sprites/Parallax Industrial/far-buildings.png" id="px_far"]\n')
    a('[ext_resource type="Texture2D" path="res://sprites/Parallax Industrial/buildings.png" id="px_perto"]\n')
    a("\n")

    for (largura, altura), nome in formas.items():
        a(retangulo(nome, largura, altura))

    a('[node name="Fase02" type="Node2D"]\n')
    a('script = ExtResource("script_fase")\n\n')

    # A cidade vista pelas janelas. Camadas do pack Parallax Industrial (CC0, Ansimuz).
    a('[node name="Parallax" type="ParallaxBackground" parent="."]\n')
    a("layer = -3\n\n")
    a('[node name="Ceu" type="ParallaxLayer" parent="Parallax"]\n')
    a("motion_scale = Vector2(0, 0)\n\n")
    a('[node name="Fundo" type="ColorRect" parent="Parallax/Ceu"]\n')
    a("offset_right = %d.0\noffset_bottom = %d.0\n" % (LARGURA, ALTURA))
    # Fim de tarde: o Dia 2 acontece mais tarde que o Dia 1, e a mudanca de luz e a
    # primeira coisa que diz ao jogador que este nao e o mesmo dia.
    a("color = Color(0.145098, 0.192157, 0.313725, 1)\nmouse_filter = 2\n\n")

    # Cada camada e repetida ate passar da largura da viewport ANTES de ligar o
    # espelhamento: o espelhamento do ParallaxLayer deixa buraco quando o bloco repetido
    # e menor que a tela (as texturas tem 213 a 272px, a viewport tem 400).
    for nome, ident, escala, largura_px, topo in [
        ("Longe", "px_bg", 0.12, 272, 30),
        ("Meio", "px_far", 0.28, 213, 55),
        ("Perto", "px_perto", 0.46, 272, 8),
    ]:
        copias = 400 // largura_px + 1
        a('[node name="%s" type="ParallaxLayer" parent="Parallax"]\n' % nome)
        a("motion_scale = Vector2(%s, 0)\n" % escala)
        a("motion_mirroring = Vector2(%d, 0)\n\n" % (largura_px * copias))
        for i in range(copias):
            a('[node name="Sprite%d" type="Sprite2D" parent="Parallax/%s"]\n' % (i, nome))
            a("position = Vector2(%d, %d)\n" % (largura_px * i, topo))
            a("centered = false\n")
            a('texture = ExtResource("%s")\n\n' % ident)

    # Parede: fechada em cima e embaixo, aberta so na altura do vidro.
    a('[node name="Parede" type="Node2D" parent="."]\n\n')
    faixa0 = VIDRO_LINHA * T
    faixa1 = (VIDRO_LINHA + VIDRO_ALTURA) * T
    cor_parede = "Color(0.239216, 0.223529, 0.34902, 1)"
    for nome, topo, base in [("Acima", 0, faixa0), ("Abaixo", faixa1, ALTURA)]:
        a('[node name="%s" type="ColorRect" parent="Parede"]\n' % nome)
        a("z_index = -12\n")
        a("offset_top = %d.0\noffset_right = %d.0\noffset_bottom = %d.0\n" % (topo, LARGURA, base))
        a("color = %s\nmouse_filter = 2\n\n" % cor_parede)
    for i, (x0, x1) in enumerate(vaos_de_parede()):
        a('[node name="Cheia%d" type="ColorRect" parent="Parede"]\n' % i)
        a("z_index = -12\n")
        a("offset_left = %d.0\noffset_top = %d.0\noffset_right = %d.0\noffset_bottom = %d.0\n"
          % (x0, faixa0, x1, faixa1))
        a("color = %s\nmouse_filter = 2\n\n" % cor_parede)

    for nome, dados, z in [("Decoracao", decoracao, -8), ("Objetos", objetos, -7),
                           ("Piso", piso, -1)]:
        a('[node name="%s" type="TileMapLayer" parent="."]\n' % nome)
        a("z_index = %d\n" % z)
        a('tile_map_data = PackedByteArray("%s")\n' % dados)
        a('tile_set = ExtResource("tileset")\n\n')

    # As duas estruturas delegaveis, em camadas proprias e quase transparentes: elas
    # PRECISAM ser visiveis antes de existirem, senao delegar parece nao ter feito nada e
    # o jogador nunca liga a acao ao efeito.
    for nome, dados in [("PonteTiles", ponte_tiles), ("EscadaTiles", escada_tiles)]:
        a('[node name="%s" type="TileMapLayer" parent="."]\n' % nome)
        a("z_index = -1\nmodulate = Color(1, 1, 1, 0.22)\n")
        a('tile_map_data = PackedByteArray("%s")\n' % dados)
        a('tile_set = ExtResource("tileset")\n\n')

    a('[node name="Colisores" type="Node2D" parent="."]\n\n')
    for nome, cx, cy, forma_id, ligado in colisores:
        a('[node name="%s" type="StaticBody2D" parent="Colisores"]\n' % nome)
        a("position = Vector2(%d, %d)\n\n" % (cx, cy))
        a('[node name="CollisionShape2D" type="CollisionShape2D" parent="Colisores/%s"]\n' % nome)
        a('shape = SubResource("%s")\n' % forma_id)
        if not ligado:
            a("disabled = true\n")
        a("\n")

    a('[node name="Camera" parent="." instance=ExtResource("cena_camera")]\n')
    a("position = Vector2(%d, %d)\n" % INICIO_JOGADOR)
    a("limit_left = 0\nlimit_top = 0\nlimit_right = %d\nlimit_bottom = %d\n\n" % (LARGURA, ALTURA))

    a('[node name="Player" parent="." instance=ExtResource("cena_player")]\n')
    a("position = Vector2(%d, %d)\n\n" % INICIO_JOGADOR)

    a('[node name="Checkpoints" type="Node2D" parent="."]\n\n')
    for i, x in enumerate(CHECKPOINTS):
        a('[node name="Checkpoint%d" type="Area2D" parent="Checkpoints"]\n' % i)
        a("position = Vector2(%d, 148)\ncollision_layer = 0\ncollision_mask = 2\n\n" % x)
        a('[node name="CollisionShape2D" type="CollisionShape2D" parent="Checkpoints/Checkpoint%d"]\n' % i)
        a('shape = SubResource("%s")\n\n' % forma_checkpoint)

    # O no Tarefas nasce so com as fixas do arquivo; o resto do dia chega pelo spawner.
    a('[node name="Tarefas" type="Node2D" parent="."]\n\n')
    for i, (x, y, cat, texto, maduro) in enumerate(TAREFAS_FIXAS):
        a('[node name="Fixa%d" parent="Tarefas" instance=ExtResource("cena_tarefa")]\n' % i)
        a("position = Vector2(%d, %d)\n" % (x, y))
        a("categoria = %d\n" % cat)
        a('texto = "%s"\n' % escapar(texto))
        if maduro:
            a('texto_maduro = "%s"\n' % escapar(maduro))
        # Toda tarefa balanca: quando so as Q4 se mexiam, o movimento entregava a
        # resposta e dava para classificar sem ler.
        a("amplitude = Vector2(0, %d)\n" % (10 if cat != 3 else 12))
        a("periodo = %s\n\n" % (2.6 if cat != 3 else 2.0))

    a('[node name="Bifurcacoes" type="Node2D" parent="."]\n\n')
    for i, (x, texto) in enumerate(BIFURCACOES):
        a('[node name="Q3%s" parent="Bifurcacoes" instance=ExtResource("cena_q3")]\n' % "ab"[i])
        a("position = Vector2(%d, %d)\n" % (x, LINHA_PISO * T))
        a('texto = "%s"\n' % escapar(texto))
        a('colega = NodePath("../../Colegas/Colega%d")\n\n' % i)

    a('[node name="Delegacoes" type="Node2D" parent="."]\n\n')
    for c in COLEGAS:
        a('[node name="%s" type="Node2D" parent="Delegacoes"]\n' % c["nome"])
        a('script = ExtResource("script_alvo")\n')
        a("position = Vector2(%d, %d)\n" % (c["alvo_x"], LINHA_PISO * T))
        a('mensagem = "%s"\n' % escapar(c["mensagem"]))
        a('corpo = NodePath("../../Colisores/%s")\n' % c["corpo"])
        a('visual = NodePath("../../%s")\n\n' % c["visual"])

    a('[node name="Colegas" type="Node2D" parent="."]\n\n')
    for i, c in enumerate(COLEGAS):
        a('[node name="Colega%d" parent="Colegas" instance=ExtResource("cena_colega")]\n' % i)
        a("position = Vector2(%d, %d)\n" % (c["x"], c["y"]))
        a('alvo = NodePath("../../Delegacoes/%s")\n' % c["nome"])
        a("velocidade = %s\n" % VELOCIDADE_COLEGA)
        a("chao_y = %s\n\n" % float(LINHA_PISO * T))

    a('[node name="Inimigos" type="Node2D" parent="."]\n\n')
    for i, (x, y, alcance_lado) in enumerate(LADROES):
        a('[node name="Ladrao%d" parent="Inimigos" instance=ExtResource("cena_ladrao")]\n' % i)
        a("position = Vector2(%d, %d)\n" % (x, y))
        a("alcance_esquerda = %d.0\nalcance_direita = %d.0\n\n" % (alcance_lado, alcance_lado))

    a('[node name="Spawner" type="Node2D" parent="."]\n')
    a('script = ExtResource("script_spawner")\n')
    a('destino_tarefas = NodePath("../Tarefas")\n')
    a('destino_notificacoes = NodePath("../Inimigos")\n\n')

    a('[node name="Saida" parent="." instance=ExtResource("cena_saida")]\n')
    a("position = Vector2(%d, %d)\n\n" % SAIDA)

    a('[node name="ZonaDeQueda" type="Area2D" parent="."]\n')
    a("position = Vector2(%d, 250)\ncollision_layer = 0\ncollision_mask = 2\n\n" % (LARGURA // 2))
    a('[node name="CollisionShape2D" type="CollisionShape2D" parent="ZonaDeQueda"]\n')
    a('shape = SubResource("%s")\n\n' % forma_queda)

    a('[node name="HUD" parent="." instance=ExtResource("cena_hud")]\n')

    texto = "".join(p)
    passos = texto.count("[ext_resource") + texto.count("[sub_resource") + 1
    texto = texto.replace("load_steps=0", "load_steps=%d" % passos, 1)

    with open(DESTINO, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)

    por_categoria: dict[int, int] = {}
    for _x, _p, cat, *_r in AGENDA:
        if cat >= 0:
            por_categoria[cat] = por_categoria.get(cat, 0) + 1
    for _x, _y, cat, *_r in TAREFAS_FIXAS:
        por_categoria[cat] = por_categoria.get(cat, 0) + 1
    por_categoria[2] = por_categoria.get(2, 0) + len(BIFURCACOES)

    print("gerado %s" % DESTINO)
    print("  %d colunas (%dpx), %d colisores, %d janelas" % (
        COLUNAS, LARGURA, len(colisores), len(JANELAS)))
    print("  tarefas por quadrante: " + "  ".join(
        "Q%d=%d" % (c + 1, por_categoria.get(c, 0)) for c in range(4)))
    print("  total de tarefas: %d" % sum(por_categoria.values()))
    print("  interrupcoes: %d" % len([e for e in AGENDA if e[2] < 0]))
    limite = DIANTEIRA_COLEGA * VELOCIDADE_COLEGA * VELOCIDADE_MAX / (
        VELOCIDADE_MAX - VELOCIDADE_COLEGA)
    for c in COLEGAS:
        d = abs(c["alvo_x"] - BIFURCACOES[c["bifurcacao"]][0])
        print("  colega -> %-16s %4dpx (%s, limite %.0f)" % (c["nome"], d, c["tipo"], limite))


if __name__ == "__main__":
    main()
