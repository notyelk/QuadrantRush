"""Gera scenes/level/fase_01.tscn a partir do layout descrito aqui embaixo.

Molde: tools/gerar_fase_02.py (mesmo vocabulario de tile, mesma escrita de cena) mais o
validador que RECUSA escrever a cena se alguma travessia
obrigatoria for impossivel.

    python tools/gerar_fase_01.py

Confira com os olhos antes de dar por pronto -- ja pegou halo em janela, quadro sobre
plataforma e parallax sem cobertura neste projeto:

    godot --path . res://tools/screenshot.tscn -- fase_01

Por que a Fase 1 passou a ser gerada: ela era a unica fase ainda montada a mao.
Com 190 colunas, mezanino, buracos de descida e um orcamento de tempo que precisa fechar
em 75-80%, mexer nela no .tscn deixou de ser viavel.

Vocabulario de tile (Little Bits Office, CC0 -- ver CREDITOS.md):
    source 5  Little_Bits_Office_Floors  piso e topo de plataforma
    source 6  Little_Bits_office_objects moveis soltos
    source 7  Little_Bits_office_walls   parede, rodape e janelas
"""

from __future__ import annotations

import base64
import re
import shutil
import sys
import math
import os
import struct

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "scenes", "level", "fase_01.tscn")

T = 16                      # lado do tile
COLUNAS = 190               # 3040px (era 2536 na versao montada a mao)
LARGURA = COLUNAS * T
ALTURA = 208

LINHA_PISO = 11             # topo do piso em y=176
LINHA_RODAPE = 10
LINHA_TETO = 0

# Faixa de parede em que as janelas ficam (linhas 3 a 7 => y 48..128).
JANELA_LINHA0 = 3
JANELA_LINHAS = 5
JANELA_COLS = 4
VIDRO_COL = 1
VIDRO_LARGURA = 2
VIDRO_LINHA = 5
VIDRO_ALTURA = 1

# fisica do jogador
#
# Estes numeros sao COPIA de scenes/player/player.gd e a razao de o validador existir.
# Se mudarem la, mudam aqui, e a fase precisa ser regerada.
VELOCIDADE_PULO = 350.0
GRAVIDADE = 980.0
VELOCIDADE_MAX = 180.0
ALTURA_PULO = VELOCIDADE_PULO ** 2 / (2 * GRAVIDADE)     # 62.5px

# Pior caso de velocidade horizontal previsto pelo design: pasta cheia (-25%), foco
# DESLIGADO. O modo foco nunca e obrigatorio, entao nao entra no pior caso; a pasta e,
# porque o jogador pode estar carregado em qualquer ponto da fase.
VELOCIDADE_PIOR_CASO = VELOCIDADE_MAX * 0.75             # 135px/s


def maxf_zero(v: float) -> float:
    """Descidas nao ajudam a alcancar mais longe do que um pulo reto na conta simples
    usada pela busca de alcancabilidade; tratar subida negativa como zero mantem o
    resultado conservador."""
    return v if v > 0.0 else 0.0


def alcance(subida_px: float, velocidade: float = VELOCIDADE_PIOR_CASO) -> float:
    """Distancia horizontal de um pulo que precisa SUBIR `subida_px`.

    Integra a trajetoria de verdade em vez de usar "altura maxima x largura maxima", que
    e a conta errada que ja produziu plataforma inalcancavel neste projeto: no instante em
    que o jogador esta la em cima, ele nao percorreu a largura toda.

    Raiz maior de 490t^2 - 350t + subida = 0 -- o instante em que ele volta aquela altura
    descendo, que e o ultimo momento util para pousar. subida negativa = pouso mais baixo.
    """
    disc = VELOCIDADE_PULO ** 2 - 2 * GRAVIDADE * subida_px
    if disc < 0:
        return -1.0                      # nao alcanca essa altura de jeito nenhum
    t = (VELOCIDADE_PULO + math.sqrt(disc)) / GRAVIDADE
    return velocidade * t


# layout
#
# Setores (x em px):
#   S0 recepcao 0-420 | S1 baias 420-1000 | S2 copa 1000-1350
#   S3 mezanino 1350-2140 | S4 distracoes 2140-2540 | S5 saida 2540-3040

CHAOS = [(0, 190)]          # o chao da Fase 1 e continuo: nao ha vao de queda no Dia 1

MEZANINO_COL0 = 86          # x=1376
MEZANINO_COL1 = 134         # x=2144
# Linha 4 (topo em y=64), e nao 5.
#
# Na linha 5 a base do mezanino ficava em y=96, e quem estivesse em pe na escada B
# (topo y=112, cabeca em y=94) passava por uma fresta de 2px. Na pratica o jogador
# ficava preso embaixo do mezanino depois de descer para pegar a Q1 da auditoria: nao
# subia, e a unica saida era voltar andando ate o comeco do setor. Reportado jogando.
#
# Na linha 4 a base vai para y=80 e sobram 14px de folga sobre a cabeca dele. De quebra,
# quem pula do chao para o degrau da Q1 deixa de bater a cabeca no mezanino no meio do
# salto: o apice do pulo leva a cabeca a y=95,5, que na linha 5 era exatamente a base.
MEZANINO_LINHA = 4          # topo em y=64

# Buracos no piso do mezanino. O primeiro e a DESCIDA DE MAO UNICA (nao ha plataforma
# embaixo dele para voltar); o segundo e por onde a escada B sobe -- ele existe para dar
# folga de cabeca, senao o jogador em pe na escada bate no mezanino.
BURACO_DESCIDA = (103, 105)     # x 1648..1680
BURACO_ESCADA_B = (116, 120)    # x 1856..1920

# Terceiro buraco: o vao da plataforma movel, no fim do mezanino. Largo DE PROPOSITO --
# o validador confere que ele nao cabe num pulo em velocidade maxima, senao a plataforma
# vira enfeite. Quem nao quiser esperar o ciclo pode simplesmente cair no chao; e por isso
# que este vao nao entra na lista de travessias obrigatorias. A ultima Q2 do mezanino fica
# em cima dele: pega-se ela andando na plataforma.
BURACO_MOVEL = (122, 131)       # x 1952..2096, 144px
# O curso e medido para que os extremos do CORPO encostem nas duas beiradas do vao, sem
# atravessar o piso do mezanino: centro de (1952+24) a (2096-24), ou seja 2024 +- 48.
# E o topo fica em y=80, igual ao do mezanino, para a plataforma ler como continuacao
# do piso e nao como degrau (topo em y=64, igual ao mezanino da linha 4).
PLATAFORMA_MOVEL = {
    "x": 2024, "y": 70, "curso": (48, 0), "periodo": 3.6, "meia_extensao": (24, 6),
}

# (col_inicio, col_fim_exclusivo, linha_do_topo). Linha 9 => y=144, 7 => y=112, 8 => y=128.
PLATAFORMAS = [
    # Degraus das quatro Q1. Existem para que a espinha da fase NAO fique na linha de
    # quem so corre: cada urgente custa um pulo deliberado.
    #
    # Isto foi bug real na primeira geracao. Com as Q1 em y=152 -- a altura do corpo de
    # quem corre no chao -- o robo "jogador apressado" do teste coletou uma delas sem
    # querer, e a fase voltou a ser resolvida andando para a direita, que e exatamente a
    # queixa que originou este redesenho. Quem pegou foi o cenario 2, nao o olho.
    (14, 18, 9),      # Q1 #1, x=250
    (54, 58, 9),      # Q1 #2, x=900
    (108, 112, 9),    # Q1 #3, x=1760 -- a que trava quem fica no mezanino
    (179, 183, 9),    # Q1 #4, x=2900
    # S1 -- esporao da primeira Q2: subir e voltar, ~3s
    (42, 45, 8),
    # S2 -- bandeja de delegar da Q3 #1
    (70, 74, 8),
    # S3 -- escada A, a entrada do mezanino
    (78, 82, 9),
    (82, 86, 7),
    # S3 -- escada B, a volta ao mezanino depois de pegar a Q1 do chao
    (112, 116, 9),
    (116, 120, 7),
    # S3 -- descida do fim do mezanino ate o chao.
    #
    # A segunda esta na linha 8, e nao na 9. Na 9 o topo dela ficava em y=144 e a base em
    # y=160, ou seja, 2px dentro da cabeca de quem anda no chao (o corpo vai de 158 a 176):
    # virava parede. E para escalar essa parede o jogador teria de pular estando embaixo da
    # plataforma anterior, que corta o pulo em y=128. Bolso sem saida -- nem humano passa.
    # Na linha 8 a base fica em y=144 e sobram 32px de passagem por baixo.
    (134, 138, 7),
    (138, 142, 8),
    # S4 -- bandejas de delegar das Q3 #2 e #3.
    #
    # A #2 comeca na coluna 143, e nao 141: em 141 ela dividia coluna com a descida do
    # mezanino (138-141, linha 9) e a folga entre as duas era ZERO -- o topo de uma em
    # y=144 e a base da outra tambem em y=144. Quem subisse na de baixo ficava entalado.
    # Foi o robo do cenario 7 que achou, travado em x=2203; nenhum teste de logica veria.
    (143, 147, 8),
    (154, 158, 8),
    # S5 -- o esporao alto da ultima Q2, em dois degraus.
    #
    # A prateleira (linha 6, topo y=96) fica 80px acima do chao e o pulo so alcanca 62,5:
    # sozinha, ela e inalcancavel.
    #
    # O degrau de baixo (linha 8) e o que torna a prateleira alcancavel: chao -> 128 sao
    # 48px, e 128 -> 96 sao 32px. Na etapa 2 e ELE que vira a EscadaDelegada, aparecendo
    # so quando a Q3 #3 for delegada. A prateleira continua sempre visivel, para o jogador
    # ver o premio antes de saber como chega nele.
    (166, 170, 8),
    (170, 174, 6),
]

# Prateleiras das caixas de saida da pasta (etapa 3). Ficam FORA da linha de corrida, um
# pulo acima do chao: entregar custa cerca de 1s de desvio. No chao elas encostariam
# sozinhas em quem passasse correndo, e a mecanica inteira -- decidir QUANDO parar para
# entregar -- deixaria de existir.
#
# As colunas foram escolhidas nos vaos entre plataformas ja existentes; o validador
# confere que nenhuma divide coluna com movel ou com outra plataforma.
PRATELEIRAS_CAIXA = [
    (60, 63, 9),      # depois do primeiro bloco de baias
    (129, 132, 9),    # sob o fim do mezanino, para quem desceu carregado
    (161, 164, 9),    # antes do trecho final
]
PLATAFORMAS += PRATELEIRAS_CAIXA

# Coluna inicial de cada bloco de janela (4 de largura, linhas 3..7). Nenhuma pode cair
# sob o mezanino nem sobre plataforma das linhas 3..7 -- o validador confere.
JANELAS = [5, 13, 22, 30, 47, 55, 63, 148, 162, 178]

# Moveis, por TIPO e nao por celula solta.
#
# Cada tipo declara o retangulo INTEIRO que ocupa no atlas. Movel de 2 colunas -- a mesa e
# (4,0)(5,0) em cima e (4,1)(5,1) embaixo -- pintado como 1 coluna vira meia mesa flutuando
# no jogo.
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
    (5, "mesa"), (11, "cadeira"), (20, "armario"), (26, "planta"), (30, "lixeira"),
    # A planta e a cadeira sairam das colunas 60/63 para 64/68: a prateleira da primeira
    # caixa de saida ocupa 60-63, e movel em cima de plataforma vira meia imagem enfiada
    # no piso (o gerador recusa isso, e recusou esta).
    (34, "mesa"), (46, "bebedouro"), (50, "mesa"), (64, "planta"), (68, "cadeira"),
    (66, "mesa"), (95, "armario"), (128, "planta"), (145, "lixeira"), (150, "mesa"),
    (160, "bebedouro"), (168, "mesa"), (175, "cadeira"), (185, "armario"),
]

INICIO_JOGADOR = (48, 160)
SAIDA = (3010, 176)

CHECKPOINTS = [400, 1000, 1400, 1800, 2200, 2600]

# tarefas
#
# (x, y, categoria, texto, amplitude). TODA tarefa balanca -- antes so as Q4
# tinham amplitude, e era isso que permitia classificar sem ler o enunciado. Amplitudes
# e periodos variados para que nem o ritmo do balanco vire dica.
#
# categoria: 0=Q1 urgente+importante, 1=Q2 importante nao urgente, 3=Q4 distracao.
# Q3 nao usa esta cena -- e bifurcacao geometrica, ver BIFURCACOES.
TAREFAS = [
    # -- S0 recepcao: o tutorial. Uma Q1 sozinha, depois uma Q4 identica, para o jogador
    #    aprender a ler o enunciado errando barato.
    (250, 120, 0, "Cliente ao telefone: contrato vence hoje", (0, -8), 2.6),
    (380, 160, 3, "Notificacao de rede social", (0, -10), 2.0),

    # -- S1 baias
    (700, 112, 1, "Planejar o roadmap do proximo trimestre", (0, -7), 3.1),
    (900, 120, 0, "Servidor de producao fora do ar", (10, 0), 2.4),
    (1040, 160, 3, "Grupo do WhatsApp apitando", (0, -12), 1.8),

    # -- S3 mezanino: as quatro Q2 que so existem la em cima
    (1450, 56, 1, "Documentar o processo da equipe", (0, -7), 2.9),
    (1580, 56, 1, "Estudar a nova ferramenta do time", (8, 0), 3.3),
    (1950, 56, 1, "Preparar a retrospectiva da sprint", (0, -6), 2.7),
    (2060, 56, 1, "Revisar o plano de contingencia do time", (0, -9), 3.5),

    # -- S3 chao: a Q1 que trava quem fica no mezanino, e as distracoes do caminho facil
    (1540, 160, 3, "Video engracado que mandaram", (0, -11), 2.1),
    (1760, 120, 0, "Auditoria chegou: relatorio agora", (0, -8), 2.5),
    (1990, 160, 3, "Feed de noticias", (11, 0), 1.9),

    # -- S4 distracoes
    (2360, 160, 3, "Fofoca no corredor", (0, -13), 1.7),
    (2620, 160, 3, "E-mail promocional", (0, -10), 2.2),

    # -- Distracoes extras. Sao a acao mais frequente da fase e o que da ritmo ao
    #    corredor; como nao pontuam quando evitadas, acrescentar nao mexe no teto de
    #    1.060 pontos nem na conta de tarefas deixadas para tras.
    (560, 160, 3, "Colega chamando para o cafe", (0, -12), 2.3),
    (1250, 160, 3, "Enquete no chat da empresa", (12, 0), 2.0),
    (1700, 160, 3, "Meme no grupo do time", (0, -14), 1.6),
    (2200, 160, 3, "Promocao relampago no aplicativo", (0, -11), 2.4),
    (2820, 160, 3, "Video novo do canal que voce segue", (10, 0), 1.9),

    # -- S5 saida
    (2760, 80, 1, "Treinar o colega que vai te substituir nas ferias", (0, -7), 3.0),
    (2900, 120, 0, "Entrega combinada para hoje as 18h", (9, 0), 2.3),
]

# (x, texto) das bifurcacoes Q3. A bandeja de delegar fica na plataforma acima de cada uma.
#
# Enunciados deliberadamente limitrofes: nenhum deles se classifica no automatico, e e
# nesse ponto que a fase deixa de testar reflexo e passa a testar julgamento.
BIFURCACOES = [
    (1160, "Reuniao de status sem pauta definida"),
    (2320, "Pedido de planilha que outro setor faz melhor"),
    (2500, "Ligacao de fornecedor para o setor errado"),
]

# O colega. Delegar a Q3 dele o levanta da bandeja: ele desce, caminha ate um alvo e o
# aciona -- ver scripts/colega.gd.
#
#   bifurcacao  indice em BIFURCACOES (de onde a delegacao parte)
#   x, y        onde ele fica sentado (pes) na bandeja, ao lado do ponto de delegar
#   alvo_x      onde o alvo dele fica
#   tipo        "perto" = paga sempre | "longe" = so paga para quem se desviou
#   corpo       nome do StaticBody2D que ele torna solido
#
# O "tipo" nao e rotulo: sai da conta dos 630px (design, secao 6.1) e o validador confere
# que a posicao escolhida realmente produz o comportamento que o design pediu. Sem essa
# conferencia, mover uma bandeja 200px transforma delegar em decoracao e ninguem
# perceberia olhando o jogo rodar.
COLEGAS = [
    {
        "bifurcacao": 2, "x": 2510, "y": 128,
        "nome": "EscadaDelegada", "alvo_x": 2760, "tipo": "perto",
        # 260px. O unico alvo que muda GEOMETRIA: sem ele a prateleira da ultima Q2 fica
        # 80px acima do chao, contra 62,5px de pulo -- inalcancavel. Ou seja, nao existem
        # 1.060 pontos sem delegar. Isso e fiel ao Quadro 1, que ja diz que delegar (+60)
        # vale mais que resolver (+40): o jogo so passou a dizer o mesmo com geometria.
        "corpo": "EscadaDelegada",
        "mensagem": "O colega baixou a escada do arquivo",
    },
]

VELOCIDADE_COLEGA = 140.0
DIANTEIRA_COLEGA = 1.0      # segundos que o jogador gasta descendo da bandeja

# Indice em PLATAFORMAS do degrau que so existe depois de delegar a Q3 #3.
#
# Ele CONTINUA na lista de plataformas, e isso e proposital: o validador de
# alcancabilidade precisa provar que a prateleira da ultima Q2 e alcancavel DEPOIS da
# delegacao. A conferencia do outro lado -- que ela e inalcancavel ANTES -- e a regra 9b.
#
# E o de baixo do esporao final (166,170,8), NAO a prateleira (170,174,6). A prateleira
# continua sempre visivel e sempre solida: o jogador precisa ver o premio antes de saber
# como se chega nele. O gerador ja nomeou a ULTIMA plataforma da lista, que
# e a prateleira -- o oposto do que o comentario dela sempre disse.
PLATAFORMA_ESCADA = (166, 170, 8)


# Caixas de saida da pasta (etapa 3). Em recuo da linha principal: entregar custa ~1s.
CAIXAS_SAIDA = [980, 2120, 2700]

# identidade visual
#
# O Dia 1 e de MANHA: ceu azul com nuvens. Isto nao e enfeite -- e o que distingue os tres
# dias de relance. A primeira geracao desta fase copiou o parallax industrial da Fase 2
# (fim de tarde, cidade verde) e o Dia 1 ficou identico ao Dia 2. Foi a captura em PNG que
# pegou, nao o teste: geometria correta, identidade errada.
CEU = "Color(0.254902, 0.650980, 0.964706, 1)"
NUVENS_REGIAO = (0, 0, 256, 48)      # PixelOffice.png
NUVENS_Y = 56

# Quadros na parede, de 320 em 320px, e o balcao da recepcao. Recortes de
# Little_Bits_office_walls.png, herdados da fase montada a mao.
QUADRO_REGIAO = (144, 80, 96, 32)

# y=28, e nao 14. O HUD cobre os primeiros ~22px da tela (relogio, contador e barra de
# percurso), e em y=14 a metade de cima de cada quadro sumia atras dele: no jogo aparecia
# meio quadro pendurado. Herdado da fase montada a mao, onde ja era assim.
QUADRO_Y = 28

# Colunas escolhidas a dedo para nao dividir espaco com janela nenhuma -- o quadro tem 6
# colunas de largura e desceu para uma faixa que encosta na das janelas. O validador
# confere coluna a coluna; esta lista nao pode ser mexida sem rodar o gerador de novo.
QUADROS_X = [c * T for c in (34, 41, 68, 76, 90, 104, 118, 132, 140, 154, 168, 184)]
BALCAO_REGIAO = (89, 80, 46, 23)
BALCAO_POS = (272, 153)

# validacao
#
# Travessias OBRIGATORIAS: (nome, x0, y0, x1, y1). Sao os pulos que a rota principal
# exige de qualquer jogador. Desvio opcional (esporao de Q2) nao entra aqui -- se ficar
# dificil, e escolha do jogador; se a rota principal ficar impossivel, e bug.

def travessias() -> list[tuple[str, float, float, float, float]]:
    return [
        # Os quatro degraus de Q1. Obrigatorios de verdade: o elevador exige as quatro
        # urgentes, entao se um destes pulos nao couber, a fase fica invencivel.
        ("degrau da Q1 #1", 210, 176, 240, 144),
        ("degrau da Q1 #2", 860, 176, 890, 144),
        ("degrau da Q1 #3", 1710, 176, 1745, 144),
        ("degrau da Q1 #4", 2860, 176, 2890, 144),
        ("escada A degrau 1", 1240, 176, 1256, 144),
        ("escada A degrau 2", 1300, 144, 1320, 112),
        ("escada A para o mezanino", 1370, 112, 1385, 64),
        ("escada B degrau 1", 1780, 176, 1800, 144),
        ("escada B degrau 2", 1850, 144, 1870, 112),
        ("escada B para o mezanino", 1900, 112, 1935, 64),
        ("bandeja da Q3 #1", 1100, 176, 1130, 128),
        ("bandeja da Q3 #2", 2230, 176, 2260, 128),
        ("bandeja da Q3 #3", 2450, 176, 2480, 128),
    ]


def validar() -> None:
    problemas: list[str] = []

    # 1. Toda travessia obrigatoria cabe no pulo real, no pior caso de velocidade.
    for nome, x0, y0, x1, y1 in travessias():
        subida = y0 - y1                      # y cresce para baixo
        if subida > ALTURA_PULO:
            problemas.append(
                "%s: sobe %.0fpx, o pulo so da %.1fpx" % (nome, subida, ALTURA_PULO))
            continue
        possivel = alcance(subida)
        preciso = abs(x1 - x0)
        if preciso > possivel:
            problemas.append(
                "%s: precisa de %.0fpx horizontais, o pulo carregado so da %.0fpx"
                % (nome, preciso, possivel))

    # 2. Nenhuma plataforma corta uma janela. Ja aconteceu duas vezes neste projeto e
    #    por isso e teste, nao cuidado.
    linhas_janela = set(range(JANELA_LINHA0, JANELA_LINHA0 + JANELA_LINHAS))
    for base in JANELAS:
        cols_janela = set(range(base, base + JANELA_COLS))
        for inicio, fim, linha in PLATAFORMAS:
            if linha in linhas_janela and cols_janela & set(range(inicio, fim)):
                problemas.append(
                    "janela na coluna %d e cortada pela plataforma %d-%d (linha %d)"
                    % (base, inicio, fim, linha))
        if MEZANINO_LINHA in linhas_janela and cols_janela & set(
                range(MEZANINO_COL0, MEZANINO_COL1)):
            problemas.append("janela na coluna %d fica atras do mezanino" % base)

    # 3. A conta dos 630px (design, secao 6.1). Com dianteira de 1s, o colega chega antes
    #    do jogador quando d < h*140*180/(180-140). Perto SEMPRE abre; longe so abre para
    #    quem se desviou. Sem esta conferencia, mover uma bandeja transforma delegar em
    #    decoracao e ninguem perceberia olhando o jogo rodar.
    limite = DIANTEIRA_COLEGA * VELOCIDADE_COLEGA * VELOCIDADE_MAX / (
        VELOCIDADE_MAX - VELOCIDADE_COLEGA)
    for c in COLEGAS:
        x_bandeja = BIFURCACOES[c["bifurcacao"]][0]
        d = abs(c["alvo_x"] - x_bandeja)
        real = "perto" if d < limite else "longe"
        if real != c["tipo"]:
            problemas.append(
                "%s: alvo a %.0fpx da bandeja e '%s' (limite %.0fpx), mas o design "
                "pede '%s'" % (c["nome"], d, real, limite, c["tipo"]))

        # O colega tem que ficar EM CIMA da bandeja da propria bifurcacao. Escorregando
        # para fora, ele aparece flutuando ao lado da plataforma.
        bandeja = [(i, f, l) for i, f, l in PLATAFORMAS
                   if i * T <= x_bandeja < f * T and l * T == c["y"]]
        if not bandeja:
            problemas.append("%s: nao ha bandeja em x=%d, linha y=%d"
                             % (c["nome"], x_bandeja, c["y"]))
        else:
            i, f, _l = bandeja[0]
            if not (i * T + 6 <= c["x"] <= f * T - 6):
                problemas.append(
                    "%s: o colega em x=%d cai fora da bandeja (%d..%d)"
                    % (c["nome"], c["x"], i * T, f * T))

    # 4. Toda tarefa balanca. E a trava da mecanica de classificacao: se alguma ficar
    #    parada enquanto as outras se mexem, o movimento volta a entregar a resposta.
    for x, _y, _cat, texto, amplitude, _periodo in TAREFAS:
        if amplitude == (0, 0):
            problemas.append("tarefa em x=%d ('%s') esta parada" % (x, texto[:32]))

    # 5. Nenhuma tarefa que exija ACAO pode estar na linha de quem so corre.
    #
    # Um jogador em pe no chao (topo y=176) ocupa mais ou menos y 146..176. Tarefa
    # centrada abaixo de y=128 encosta nele sozinha, sem que ele decida nada -- e a fase
    # volta a ser resolvida segurando a seta para a direita, que e a queixa que originou
    # este redesenho. Q4 e o contrario: ela DEVE estar nessa faixa, porque desviar e a
    # acao correta e precisa custar alguma coisa.
    # Numeros derivados da geometria real, nao chutados. Em pe no chao (topo y=176) a
    # origem do jogador fica em 160 e a capsula de player.tscn ocupa de -2 a +16 em torno
    # dela: 158..176. A area de contato da tarefa tem raio 8. Logo ha encosto quando
    #     y + 8 >= 158  e  y - 8 <= 176   =>   150 <= y <= 184
    CORPO_TOPO, CORPO_BASE, RAIO_TAREFA = 158.0, 176.0, 8.0
    ENCOSTA_DE = CORPO_TOPO - RAIO_TAREFA      # 150
    ENCOSTA_ATE = CORPO_BASE + RAIO_TAREFA     # 184
    for x, y, cat, texto, *_ in TAREFAS:
        if cat in (0, 1) and y >= ENCOSTA_DE:
            problemas.append(
                "tarefa Q%d em x=%d ('%s') esta em y=%d, ao alcance de quem so corre "
                "(precisa de y < %d)" % (cat + 1, x, texto[:28], y, ENCOSTA_DE))
        if cat == 3 and not (ENCOSTA_DE <= y <= ENCOSTA_ATE):
            problemas.append(
                "distracao em x=%d esta em y=%d, fora da faixa que encosta em quem corre "
                "(%d..%d) -- desviar dela nao custaria nada"
                % (x, y, ENCOSTA_DE, ENCOSTA_ATE))

    # 6. Duas plataformas que dividem coluna precisam de folga para o jogador caber
    #    entre elas. A capsula de player.tscn tem 18px de altura; abaixo disso ele fica
    #    entalado, sem conseguir andar nem pular, e a fase trava sem nenhum erro no
    #    console. Aconteceu de verdade (bandeja da Q3 #2 sobre a descida do mezanino) e
    #    quem achou foi o robo que anda a pe, depois de a cena ja ter sido gerada.
    ALTURA_JOGADOR = 18
    # O mezanino entra pelas colunas que ele REALMENTE ocupa, e nao pelo intervalo cheio:
    # as escadas sobem exatamente por baixo dos buracos dele, e tratar o piso como macico
    # acusaria justamente a folga que os buracos existem para criar.
    todas = [(set(range(i, j)), k) for i, j, k in PLATAFORMAS]
    todas.append((set(cols_do_mezanino()), MEZANINO_LINHA))
    for a in range(len(todas)):
        for b in range(a + 1, len(todas)):
            cols_a, la = todas[a]
            cols_b, lb = todas[b]
            if not (cols_a & cols_b):
                continue
            baixa, alta = (la, lb) if la > lb else (lb, la)
            folga = baixa * T - (alta * T + T)
            if folga < ALTURA_JOGADOR + 2:
                problemas.append(
                    "plataformas das linhas %d e %d dividem coluna com folga de %dpx: "
                    "o jogador (%dpx) fica entalado" % (alta, baixa, folga, ALTURA_JOGADOR))

    # 7. Todo degrau que o jogador precisa ESCALAR desde o chao precisa de teto livre.
    #
    # Um degrau da linha 9 tem base em y=160, dois pixels dentro da cabeca de quem anda no
    # chao: ele barra a passagem e so se vence pulando. Se houver outra plataforma logo
    # acima do ponto de impulso, o pulo bate nela antes de chegar ao topo do degrau e o
    # jogador fica preso num bolso, sem erro nenhum no console. Aconteceu na coluna 138.
    LINHA_LIVRE_ACIMA = 6      # linha 6 ou mais alta nao atrapalha o pulo de um degrau
    for inicio, fim, linha in PLATAFORMAS:
        if linha < 9:
            continue           # nao e degrau de chao: passa-se por baixo
        aproximacao = set(range(inicio - 2, fim))
        for i2, f2, l2 in PLATAFORMAS:
            if (i2, f2, l2) == (inicio, fim, linha):
                continue
            if LINHA_LIVRE_ACIMA < l2 < linha and (aproximacao & set(range(i2, f2))):
                problemas.append(
                    "degrau da coluna %d (linha %d) tem a plataforma %d-%d (linha %d) por "
                    "cima do impulso: o pulo bate nela e o jogador fica preso"
                    % (inicio, linha, i2, f2, l2))

    # 8. Toda travessia obrigatoria precisa de TETO, e nao so de alcance.
    #
    # A regra 1 confere se o pulo chega la; esta confere se ha espaco para faze-lo. O
    # jogador que pousa numa plataforma de topo y fica com a cabeca em y-18, e se houver
    # piso logo acima disso ele nao cabe -- fica preso embaixo, sem erro nenhum no
    # console. Caso concreto: escada B com o mezanino na linha 5 deixava uma fresta de
    # 2px, e quem descia para pegar a Q1 da auditoria nao conseguia mais subir.
    ocupacao: dict[int, list[tuple[float, float]]] = {}
    for inicio, fim, linha in PLATAFORMAS:
        for c in range(inicio, fim):
            ocupacao.setdefault(c, []).append((linha * T, linha * T + T))
    for c in cols_do_mezanino():
        ocupacao.setdefault(c, []).append((MEZANINO_LINHA * T, MEZANINO_LINHA * T + T))

    for nome, x0, y0, x1, y1 in travessias():
        cabeca = y1 - ALTURA_JOGADOR
        for c in range(int(min(x0, x1)) // T, int(max(x0, x1)) // T + 1):
            for topo_p, base_p in ocupacao.get(c, []):
                # Um piso cuja BASE fica entre a cabeca do jogador e os pes dele no pouso
                # e um teto baixo demais para essa travessia.
                if cabeca < base_p <= y1:
                    problemas.append(
                        "%s: na coluna %d ha piso ate y=%.0f e a cabeca do jogador chega "
                        "a y=%.0f -- ele nao cabe" % (nome, c, base_p, cabeca))

    # 9. TODA superficie tem que ser alcancavel a partir do chao, pulo a pulo.
    #
    # As regras 1 e 8 conferem as travessias declaradas na lista. Esta nao depende da
    # lista: faz uma busca em largura a partir do chao e acusa qualquer plataforma que
    # ninguem consegue pisar. Caso concreto: a prateleira da ultima Q2 ficou 80px acima
    # do chao contra um pulo de 62,5.
    #
    # Usa velocidade MAXIMA: a pergunta aqui e "existe algum jeito?", nao "e confortavel?".
    superficies = [(set(range(i, j)), k * T) for i, j, k in PLATAFORMAS]
    superficies.append((set(cols_do_mezanino()), MEZANINO_LINHA * T))
    mov = PLATAFORMA_MOVEL
    cols_mov = range((mov["x"] - mov["curso"][0] - mov["meia_extensao"][0]) // T,
                     (mov["x"] + mov["curso"][0] + mov["meia_extensao"][0]) // T + 1)
    superficies.append((set(cols_mov), mov["y"] - mov["meia_extensao"][1]))

    CHAO = (set(range(COLUNAS)), LINHA_PISO * T)
    alcancadas = [CHAO]
    mudou = True
    while mudou:
        mudou = False
        for cols_b, topo_b in superficies:
            if any(cols_b == c and topo_b == t for c, t in alcancadas):
                continue
            for cols_a, topo_a in alcancadas:
                subida = topo_a - topo_b
                if subida > ALTURA_PULO:
                    continue
                # Distancia horizontal entre os dois trechos, em colunas.
                if cols_a & cols_b:
                    dist = 0.0
                else:
                    dist = min(abs(a - b) for a in cols_a for b in cols_b) * T
                if dist <= alcance(maxf_zero(subida), VELOCIDADE_MAX):
                    alcancadas.append((cols_b, topo_b))
                    mudou = True
                    break

    for cols_b, topo_b in superficies:
        if not any(cols_b == c and topo_b == t for c, t in alcancadas):
            problemas.append(
                "a superficie de topo y=%d nas colunas %d-%d nao e alcancavel por pulo "
                "nenhum a partir do chao" % (topo_b, min(cols_b), max(cols_b)))

    # 10. O vao da plataforma movel nao pode caber num pulo. Se couber, ninguem espera o
    #    ciclo e a plataforma nao decide nada -- vira enfeite caro. Aqui a conta usa
    #    velocidade MAXIMA, nao o pior caso: e o jogador mais capaz que precisa nao
    #    conseguir.
    largura_vao = (BURACO_MOVEL[1] - BURACO_MOVEL[0]) * T
    pulo_cheio = alcance(0.0, VELOCIDADE_MAX)
    if largura_vao <= pulo_cheio:
        problemas.append(
            "o vao da plataforma movel tem %dpx e o pulo em velocidade maxima alcanca "
            "%.0fpx: da para pular e a plataforma vira enfeite"
            % (largura_vao, pulo_cheio))

    # 8. Nenhum quadro de parede invade a faixa das janelas nem encosta numa plataforma.
    #    "Quadro colidindo com plataforma" ja foi bug real nesta fase, e quadro sobre
    #    janela taparia a cidade do parallax.
    quadro_base = QUADRO_Y + QUADRO_REGIAO[3]

    # O quadro nao pode ficar embaixo do HUD, que ocupa a faixa de cima da tela. Meio
    # quadro escondido atras do relogio foi defeito real, reportado jogando.
    ALTURA_HUD = 24
    if QUADRO_Y < ALTURA_HUD:
        problemas.append(
            "os quadros comecam em y=%d e o HUD cobre ate y=%d: metade some atras dele"
            % (QUADRO_Y, ALTURA_HUD))

    # Janela e quadro na mesma coluna se sobrepoem visualmente. Conferido COLUNA A COLUNA,
    # e nao pela faixa inteira: desde que os quadros desceram para perto da altura das
    # janelas, a unica coisa que os separa e nao dividirem coluna.
    faixa_janela0 = JANELA_LINHA0 * T
    faixa_janela1 = (JANELA_LINHA0 + JANELA_LINHAS) * T
    if quadro_base > faixa_janela0 and QUADRO_Y < faixa_janela1:
        for x in QUADROS_X:
            cols_q = set(range(x // T, (x + QUADRO_REGIAO[2]) // T))
            for base in JANELAS:
                if cols_q & set(range(base, base + JANELA_COLS)):
                    problemas.append(
                        "o quadro em x=%d divide coluna com a janela da coluna %d"
                        % (x, base))

    for x in QUADROS_X:
        col0, col1 = x // T, (x + QUADRO_REGIAO[2]) // T
        for inicio, fim, linha in PLATAFORMAS:
            topo = linha * T
            if topo < quadro_base and set(range(col0, col1)) & set(range(inicio, fim)):
                problemas.append(
                    "quadro em x=%d bate na plataforma %d-%d (topo y=%d)"
                    % (x, inicio, fim, topo))

    # 9. A Q2 do esporao final tem que estar atras da EscadaDelegada -- e o que garante
    #    que nao existem 1.060 pontos sem delegar.
    x_escada = [c["alvo_x"] for c in COLEGAS if c["nome"] == "EscadaDelegada"]
    if x_escada:
        q2_alta = [(x, y) for x, y, cat, *_ in TAREFAS if cat == 1 and y < 96]
        perto = [(x, y) for x, y in q2_alta if abs(x - x_escada[0]) < 64]
        if not perto:
            problemas.append(
                "nenhuma Q2 alta perto da EscadaDelegada: delegar deixa de ser exigido "
                "para o placar maximo")

        # 9b. E ela precisa ser INALCANCAVEL sem o degrau. Sem esta conta a regra acima e
        #     so uma posicao bonita: bastaria a prateleira estar a um pulo do chao para o
        #     jogador pegar a Q2 ignorando o colega, e a promessa "nao existem 1.060
        #     pontos sem delegar" viraria mentira sem ninguem notar.
        #
        #     Alcance vertical de um pulo do chao: a origem do jogador sobe ALTURA_PULO e
        #     o corpo dele vai de origem-2 a origem+16. A tarefa tem raio de contato 8.
        chao_origem = LINHA_PISO * T - 16
        topo_corpo = chao_origem - ALTURA_PULO - 2
        for x, y in perto:
            if y + 8 >= topo_corpo:
                problemas.append(
                    "a Q2 de x=%d (y=%d) e alcancavel do chao sem a EscadaDelegada "
                    "(o corpo chega a y=%.1f)" % (x, y, topo_corpo))

        # 9c. E o degrau que a destranca tem de ser mesmo o (166,170,8), nao a prateleira.
        i, f, linha = PLATAFORMA_ESCADA
        if PLATAFORMA_ESCADA not in PLATAFORMAS or not (
                i * T <= x_escada[0] - 60 and linha == 8):
            problemas.append(
                "PLATAFORMA_ESCADA aponta para (%d,%d,linha %d), que nao e o degrau de "
                "acesso da prateleira" % (i, f, linha))

    # 10. As caixas de saida da pasta.
    #
    #     Elas tem de ficar ACIMA da linha de quem corre. Uma caixa no chao encostaria
    #     sozinha em qualquer um que passasse, a pasta se esvaziaria de graca, e a unica
    #     decisao da mecanica -- QUANDO parar para entregar -- deixaria de existir. E o
    #     mesmo defeito que as Q1 em y=152 tinham na primeira geracao desta fase, achado
    #     pelo robo apressado e nao pelo olho.
    for inicio, fim, linha in PRATELEIRAS_CAIXA:
        if linha >= LINHA_PISO:
            problemas.append("caixa de saida nas colunas %d-%d esta na linha de corrida"
                             % (inicio, fim))
        for outra in PLATAFORMAS:
            if outra == (inicio, fim, linha):
                continue
            if set(range(inicio, fim)) & set(range(outra[0], outra[1])):
                problemas.append(
                    "caixa de saida nas colunas %d-%d divide coluna com a plataforma "
                    "%d-%d" % (inicio, fim, outra[0], outra[1]))

    #     E precisam estar espalhadas. Tres caixas juntas seriam uma so, e o jogador
    #     passaria a maior parte do corredor carregado sem ter onde entregar -- o que
    #     transformaria a pasta em imposto fixo em vez de decisao. 450px sao cerca de
    #     2,5s correndo -- tempo de sobra para acumular carga entre uma caixa e a outra.
    centros = sorted((i + f) * T // 2 for i, f, _l in PRATELEIRAS_CAIXA)
    for x_a, x_b in zip(centros, centros[1:]):
        if x_b - x_a < 450:
            problemas.append("caixas de saida em x=%d e x=%d estao perto demais"
                             % (x_a, x_b))
    if centros[0] > LARGURA // 3:
        problemas.append("a primeira caixa de saida so aparece em x=%d, tarde demais "
                         "para o jogador descobrir a mecanica" % centros[0])

    if problemas:
        print("cena NAO gerada -- %d problema(s) de geometria:" % len(problemas))
        for p in problemas:
            print("  * %s" % p)
        raise SystemExit(1)

    print("validacao ok: %d travessias, %d janelas, %d tarefas, %d colegas" % (
        len(travessias()), len(JANELAS), len(TAREFAS), len(COLEGAS)))


# tile_map_data


def celulas_para_dados(celulas: list[tuple[int, int, int, int, int, int]]) -> str:
    """(col, linha, source, atlas_x, atlas_y, alternativa) -> base64 do PackedByteArray."""
    bruto = b"\x00\x00" + b"".join(struct.pack("<6h", *c) for c in celulas)
    return base64.b64encode(bruto).decode()


def par_do_piso(col: int, linha_topo: bool) -> tuple[int, int]:
    if linha_topo:
        return (3, 1) if col % 2 == 0 else (4, 1)
    return (3, 2) if col % 2 == 0 else (4, 2)


def cols_do_mezanino() -> list[int]:
    buracos = (set(range(*BURACO_DESCIDA)) | set(range(*BURACO_ESCADA_B))
               | set(range(*BURACO_MOVEL)))
    return [c for c in range(MEZANINO_COL0, MEZANINO_COL1) if c not in buracos]


def camada_piso() -> list:
    celulas = []
    for inicio, fim in CHAOS:
        for col in range(inicio, fim):
            celulas.append((col, LINHA_PISO, 5) + par_do_piso(col, True) + (0,))
            celulas.append((col, LINHA_PISO + 1, 5) + par_do_piso(col, False) + (0,))
    escada = PLATAFORMA_ESCADA
    for plataforma in PLATAFORMAS:
        # O degrau da EscadaDelegada sai daqui e vai para camada propria: ele precisa
        # aparecer e desaparecer, e uma TileMapLayer inteira nao pode ser escondida por
        # causa de quatro celulas.
        if plataforma == escada:
            continue
        inicio, fim, linha = plataforma
        for col in range(inicio, fim):
            celulas.append((col, linha, 5) + par_do_piso(col, True) + (0,))
    for col in cols_do_mezanino():
        celulas.append((col, MEZANINO_LINHA, 5) + par_do_piso(col, True) + (0,))
    return celulas


def camada_escada() -> list:
    """So os tiles do degrau que a Q3 #3 destranca."""
    inicio, fim, linha = PLATAFORMA_ESCADA
    return [(col, linha, 5) + par_do_piso(col, True) + (0,) for col in range(inicio, fim)]


def camada_decoracao() -> list:
    celulas = []
    for col in range(COLUNAS):
        celulas.append((col, LINHA_TETO, 7, 3, 6, 0))
        celulas.append((col, LINHA_RODAPE, 7, 3, 6, 0))
    for base in JANELAS:
        for dx in range(JANELA_COLS):
            for dy in range(JANELA_LINHAS):
                celulas.append((base + dx, JANELA_LINHA0 + dy, 7, 1 + dx, dy, 0))
    return celulas


def camada_objetos() -> list:
    """Moveis soltos, em camada propria.

    Camada separada da decoracao porque uma celula guarda UM tile: quando os dois moravam
    juntos, 22 celulas de movel apagavam a parede embaixo de si e o resultado parecia
    "PNG quebrado".
    """
    ocupadas = set()
    for inicio, fim, linha in PLATAFORMAS:
        if linha == 9:
            ocupadas.update(range(inicio, fim))

    celulas = []
    for col, tipo in MOVEIS:
        largura, linha0, grade = TIPOS_DE_MOVEL[tipo]
        for dc in range(largura):
            if col + dc in ocupadas:
                raise SystemExit(
                    "movel '%s' na coluna %d invade a plataforma da coluna %d"
                    % (tipo, col, col + dc))
        for dl, fileira in enumerate(grade):
            for dc, (ax, ay) in enumerate(fileira):
                celulas.append((col + dc, linha0 + dl, 6, ax, ay, 0))
    return celulas


def vaos_de_parede() -> list[tuple[int, int]]:
    """Trechos (x0, x1) da faixa do vidro que continuam sendo parede fechada.

    Derivado das colunas de janela, nunca digitado a mao: e assim que a cidade do parallax
    aparece exatamente atras do vidro e em nenhum outro lugar.
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


def blocos_do_mezanino() -> list[tuple[int, int]]:
    """Faixas continuas (col_inicio, col_fim) do piso do mezanino, para virar colisor."""
    cols = cols_do_mezanino()
    blocos = []
    inicio = cols[0]
    anterior = cols[0]
    for col in cols[1:]:
        if col != anterior + 1:
            blocos.append((inicio, anterior + 1))
            inicio = col
        anterior = col
    blocos.append((inicio, anterior + 1))
    return blocos


# Camadas que uma pessoa pinta a mao no editor. O gerador as recalcula a partir dos dados
# aqui de cima, entao regravar a cena apagaria qualquer ajuste feito no Godot. Elas sao
# copiadas da cena que ja esta em disco, a menos que se peca --repintar.
CAMADAS_PINTADAS = ("Decoracao", "Objetos", "Piso")

_BLOCO = r'\[node name="%s" type="TileMapLayer".*?(?=\n\[node |\Z)'
_DADOS = r'tile_map_data = PackedByteArray\("([^"]*)"\)'


def _dados_da_camada(texto, nome):
    bloco = re.search(_BLOCO % re.escape(nome), texto, re.S)
    if bloco is None:
        return None
    dados = re.search(_DADOS, bloco.group(0))
    return dados.group(1) if dados else None


def _trocar_dados(texto, nome, dados):
    def troca(m):
        return re.sub(r'(tile_map_data = PackedByteArray\(")[^"]*("\))',
                      lambda n: n.group(1) + dados + n.group(2), m.group(0), count=1)

    return re.sub(_BLOCO % re.escape(nome), troca, texto, count=1, flags=re.S)


def preservar_pintura(texto, repintar):
    """Mantem o desenho de tile que ja estiver na cena em disco."""
    if repintar or not os.path.exists(DESTINO):
        return texto
    with open(DESTINO, encoding="utf-8") as f:
        antigo = f.read()
    for nome in CAMADAS_PINTADAS:
        em_disco = _dados_da_camada(antigo, nome)
        if em_disco is None or em_disco == _dados_da_camada(texto, nome):
            continue
        texto = _trocar_dados(texto, nome, em_disco)
        print("  mantida a pintura da camada %s (--repintar descarta)" % nome)
    return texto


def guardar_copia():
    """Copia a cena atual para .anterior antes de sobrescrever."""
    if os.path.exists(DESTINO):
        shutil.copyfile(DESTINO, DESTINO + ".anterior")


def main() -> None:
    validar()

    piso = celulas_para_dados(camada_piso())
    decoracao = celulas_para_dados(camada_decoracao())
    objetos = celulas_para_dados(camada_objetos())
    escada = celulas_para_dados(camada_escada())

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
        colisores.append(("Chao%d" % i, cx, 192, forma(largura, 32)))
    escada_idx = PLATAFORMAS.index(PLATAFORMA_ESCADA)
    for i, (inicio, fim, linha) in enumerate(PLATAFORMAS):
        largura = (fim - inicio) * T
        cx = inicio * T + largura // 2
        cy = linha * T + 8
        nome = "EscadaDelegada" if i == escada_idx else "Plataforma%d" % i
        colisores.append((nome, cx, cy, forma(largura, 16)))
    for i, (inicio, fim) in enumerate(blocos_do_mezanino()):
        largura = (fim - inicio) * T
        cx = inicio * T + largura // 2
        cy = MEZANINO_LINHA * T + 8
        colisores.append(("Mezanino%d" % i, cx, cy, forma(largura, 16)))

    # Fecha as duas pontas do corredor: a camera tem limite, o corpo do jogador nao.
    for nome, cx in [("BordaEsquerda", -8), ("BordaDireita", LARGURA + 8)]:
        colisores.append((nome, cx, ALTURA // 2, forma(16, ALTURA * 3)))

    forma_checkpoint = forma(8, 56)
    forma_queda = forma(LARGURA, 60)

    p = []
    a = p.append
    a("[gd_scene load_steps=%d format=3]\n\n" % 0)  # corrigido no fim

    a('[ext_resource type="Script" path="res://scripts/fase_01.gd" id="script_fase"]\n')
    a('[ext_resource type="TileSet" path="res://scenes/tiles/escritorio.tres" id="tileset"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/level/camera.tscn" id="cena_camera"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="cena_player"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/tarefa.tscn" id="cena_tarefa"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/bifurcacao_q3.tscn" id="cena_q3"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/tasks/saida.tscn" id="cena_saida"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/colega.tscn" id="cena_colega"]\n')
    a('[ext_resource type="Script" path="res://scripts/alvo_delegado.gd" id="script_alvo"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/caixa_saida.tscn" id="cena_caixa"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/prazo.tscn" id="cena_prazo"]\n')
    a('[ext_resource type="PackedScene" path="res://entities/plataforma_movel.tscn" id="cena_movel"]\n')
    a('[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="cena_hud"]\n')
    a('[ext_resource type="Texture2D" path="res://sprites/PixelOffice/PixelOffice.png" id="tex_nuvens"]\n')
    a('[ext_resource type="Texture2D" path="res://sprites/Little Bits Office/Office tiles/Little_Bits_office_walls.png" id="tex_parede"]\n')
    a("\n")

    for nome, ident, regiao in [
        ("AtlasNuvens", "tex_nuvens", NUVENS_REGIAO),
        ("AtlasQuadro", "tex_parede", QUADRO_REGIAO),
        ("AtlasBalcao", "tex_parede", BALCAO_REGIAO),
    ]:
        a('[sub_resource type="AtlasTexture" id="%s"]\n' % nome)
        a('atlas = ExtResource("%s")\n' % ident)
        a("region = Rect2(%d, %d, %d, %d)\n\n" % regiao)

    for (largura, altura), nome in formas.items():
        a(retangulo(nome, largura, altura))

    a('[node name="Fase01" type="Node2D"]\n')
    a('script = ExtResource("script_fase")\n\n')

    a('[node name="Parallax" type="ParallaxBackground" parent="."]\n')
    a("layer = -3\n\n")
    a('[node name="Ceu" type="ParallaxLayer" parent="Parallax"]\n')
    a("motion_scale = Vector2(0, 0)\n\n")
    a('[node name="Fundo" type="ColorRect" parent="Parallax/Ceu"]\n')
    a("offset_right = %d.0\noffset_bottom = %d.0\n" % (LARGURA, ALTURA))
    a("color = %s\nmouse_filter = 2\n\n" % CEU)

    # Uma camada so, com espelhamento de 256px -- a largura da propria faixa de nuvem.
    # A Fase 2 precisa de tres camadas porque a cidade tem profundidade; um ceu nao tem.
    a('[node name="Nuvens" type="ParallaxLayer" parent="Parallax"]\n')
    a("motion_scale = Vector2(0.25, 0)\n")
    a("motion_mirroring = Vector2(%d, 0)\n\n" % NUVENS_REGIAO[2])
    a('[node name="Sprite2D" type="Sprite2D" parent="Parallax/Nuvens"]\n')
    a("position = Vector2(0, %d)\n" % NUVENS_Y)
    a("centered = false\n")
    a('texture = SubResource("AtlasNuvens")\n\n')

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

    for nome, dados, z in [("Decoracao", decoracao, -8), ("Objetos", objetos, -7), ("Piso", piso, -1)]:
        a('[node name="%s" type="TileMapLayer" parent="."]\n' % nome)
        a("z_index = %d\n" % z)
        a('tile_map_data = PackedByteArray("%s")\n' % dados)
        a('tile_set = ExtResource("tileset")\n\n')

    # O degrau que so aparece depois de delegar a Q3 #3, em camada propria para poder ser
    # escondido. Nasce fantasma (alfa 0,22) e nao invisivel: o jogador tem de VER que ali
    # poderia haver um degrau, senao a recompensa de delegar nao ensina nada.
    a('[node name="EscadaTiles" type="TileMapLayer" parent="."]\n')
    a("modulate = Color(1, 1, 1, 0.22)\nz_index = -1\n")
    a('tile_map_data = PackedByteArray("%s")\n' % escada)
    a('tile_set = ExtResource("tileset")\n\n')

    # Quadros na parede e o balcao da recepcao. Ficam em z_index -9, entre a parede
    # (-12) e a decoracao de tile (-8), e acima da faixa das janelas -- ver validacao.
    a('[node name="DecorSprites" type="Node2D" parent="."]\n\n')
    for i, x in enumerate(QUADROS_X):
        a('[node name="Quadro%d" type="Sprite2D" parent="DecorSprites"]\n' % i)
        a("z_index = -9\n")
        a("position = Vector2(%d, %d)\n" % (x, QUADRO_Y))
        a("centered = false\n")
        a('texture = SubResource("AtlasQuadro")\n\n')
    a('[node name="Balcao" type="Sprite2D" parent="DecorSprites"]\n')
    a("z_index = -9\n")
    a("position = Vector2(%d, %d)\n" % BALCAO_POS)
    a("centered = false\n")
    a('texture = SubResource("AtlasBalcao")\n\n')

    a('[node name="Colisores" type="Node2D" parent="."]\n\n')
    for nome, cx, cy, forma_id in colisores:
        a('[node name="%s" type="StaticBody2D" parent="Colisores"]\n' % nome)
        a("position = Vector2(%d, %d)\n\n" % (cx, cy))
        a('[node name="CollisionShape2D" type="CollisionShape2D" parent="Colisores/%s"]\n' % nome)
        a('shape = SubResource("%s")\n\n' % forma_id)

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

    a('[node name="Tarefas" type="Node2D" parent="."]\n\n')
    for i, (x, y, cat, texto, amplitude, periodo) in enumerate(TAREFAS):
        a('[node name="Tarefa%02d" parent="Tarefas" instance=ExtResource("cena_tarefa")]\n' % i)
        a("position = Vector2(%d, %d)\n" % (x, y))
        if cat:
            a("categoria = %d\n" % cat)
        a('texto = "%s"\n' % texto)
        a("amplitude = Vector2(%d, %d)\n" % amplitude)
        a("periodo = %s\n\n" % periodo)

    a('[node name="Bifurcacoes" type="Node2D" parent="."]\n\n')
    for i, (x, texto) in enumerate(BIFURCACOES):
        a('[node name="Q3%s" parent="Bifurcacoes" instance=ExtResource("cena_q3")]\n' % "abc"[i])
        a("position = Vector2(%d, 176)\n" % x)
        a('texto = "%s"\n' % texto)
        colega = [j for j, c in enumerate(COLEGAS) if c["bifurcacao"] == i]
        if colega:
            a('colega = NodePath("../../Colegas/Colega%d")\n' % colega[0])
        a("\n")

    # --- delegacao: o alvo primeiro, o colega depois (ler nesta ordem tambem ajuda)
    a('[node name="Delegacoes" type="Node2D" parent="."]\n\n')
    for c in COLEGAS:
        a('[node name="%s" type="Node2D" parent="Delegacoes"]\n' % c["nome"])
        a('script = ExtResource("script_alvo")\n')
        a("position = Vector2(%d, %d)\n" % (c["alvo_x"], LINHA_PISO * T))
        if c["mensagem"]:
            a('mensagem = "%s"\n' % c["mensagem"])
        if c["corpo"]:
            a('corpo = NodePath("../../Colisores/%s")\n' % c["corpo"])
            a('visual = NodePath("../../EscadaTiles")\n')
        a("\n")

    a('[node name="Colegas" type="Node2D" parent="."]\n\n')
    for i, c in enumerate(COLEGAS):
        a('[node name="Colega%d" parent="Colegas" instance=ExtResource("cena_colega")]\n' % i)
        a("position = Vector2(%d, %d)\n" % (c["x"], c["y"]))
        a('alvo = NodePath("../../Delegacoes/%s")\n' % c["nome"])
        a("velocidade = %s\n" % VELOCIDADE_COLEGA)
        a("chao_y = %s\n\n" % float(LINHA_PISO * T))

    a('[node name="CaixasSaida" type="Node2D" parent="."]\n\n')
    for i, (inicio, fim, linha) in enumerate(PRATELEIRAS_CAIXA):
        cx = inicio * T + (fim - inicio) * T // 2
        a('[node name="Caixa%d" parent="CaixasSaida" instance=ExtResource("cena_caixa")]\n' % i)
        a("position = Vector2(%d, %d)\n\n" % (cx, linha * T))

    # O no chama-se Moveis para casar com a Fase 1 anterior, que ja tinha plataformas
    # moveis aqui -- assim o teste continua procurando no mesmo lugar.
    a('[node name="Moveis" type="Node2D" parent="."]\n\n')
    a('[node name="Andaime" parent="Moveis" instance=ExtResource("cena_movel")]\n')
    a("position = Vector2(%d, %d)\n" % (PLATAFORMA_MOVEL["x"], PLATAFORMA_MOVEL["y"]))
    a("curso = Vector2(%d, %d)\n" % PLATAFORMA_MOVEL["curso"])
    a("periodo = %s\n" % PLATAFORMA_MOVEL["periodo"])
    a("meia_extensao = Vector2(%d, %d)\n\n" % PLATAFORMA_MOVEL["meia_extensao"])

    a('[node name="Inimigos" type="Node2D" parent="."]\n\n')
    a('[node name="Prazo" parent="Inimigos" instance=ExtResource("cena_prazo")]\n')
    # y=177, e nao 160 (que e a origem do JOGADOR) nem 176 (o topo do piso).
    #
    # O urso nao tem gravidade -- prazo.gd move a posicao direto, sem move_and_slide --
    # entao ele fica exatamente na altura que a cena disser, para sempre. O colisor dele
    # esta em (0,-12) com 22px de altura (entities/prazo.tscn), ou seja, os pes ficam em
    # origem-1. Para os pes encostarem no piso (topo y=176) a origem precisa ser 177 --
    # nao 176, e muito menos a linha do piso.
    # x=8: o urso abre a fase colado no calcanhar do jogador (que nasce em x=48), e
    # nao entrando em quadro depois.
    a("position = Vector2(8, %d)\n\n" % (LINHA_PISO * T + 1))

    a('[node name="Saida" parent="." instance=ExtResource("cena_saida")]\n')
    a("position = Vector2(%d, %d)\n\n" % SAIDA)

    a('[node name="ZonaDeQueda" type="Area2D" parent="."]\n')
    a("position = Vector2(%d, 260)\ncollision_layer = 0\ncollision_mask = 2\n\n" % (LARGURA // 2))
    a('[node name="CollisionShape2D" type="CollisionShape2D" parent="ZonaDeQueda"]\n')
    a('shape = SubResource("%s")\n\n' % forma_queda)

    a('[node name="HUD" parent="." instance=ExtResource("cena_hud")]\n')

    texto = "".join(p)
    passos = texto.count("[ext_resource") + texto.count("[sub_resource") + 1
    texto = texto.replace("load_steps=0", "load_steps=%d" % passos, 1)

    texto = preservar_pintura(texto, "--repintar" in sys.argv)
    guardar_copia()
    with open(DESTINO, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)

    print("gerado %s" % DESTINO)
    print("  %d colunas (%dpx), %d colisores, %d janelas" % (
        COLUNAS, LARGURA, len(colisores), len(JANELAS)))
    print("  tarefas: %d  bifurcacoes Q3: %d  checkpoints: %d" % (
        len(TAREFAS), len(BIFURCACOES), len(CHECKPOINTS)))
    for c in COLEGAS:
        x_bandeja = BIFURCACOES[c["bifurcacao"]][0]
        print("  colega -> %-17s %5dpx (%s)" % (
            c["nome"], abs(c["alvo_x"] - x_bandeja), c["tipo"]))
    print("  caixas de saida: %s"
          % [(i + f) * T // 2 for i, f, _l in PRATELEIRAS_CAIXA])
    print("  mezanino: cols %d-%d, %d blocos de colisor" % (
        MEZANINO_COL0, MEZANINO_COL1, len(blocos_do_mezanino())))


if __name__ == "__main__":
    main()
