"""Gera scenes/level/fase_03.tscn — a arena da fase final ("O Chefe").

Rodar:  python tools/gerar_fase_03.py

── O que este script escreve, e o que ele NAO escreve ────────────────────────────────
Escreve a CASCA ESTATICA da arena: piso, paredes, plataformas do mezanino, pedestais dos
cantos de baixo, o poco de queda, o parallax pela janela e os nos comuns que fase_base.gd
exige (Player, HUD, Saida, Tarefas, Bifurcacoes, Checkpoints, ZonaDeQueda, Inimigos).

NAO escreve o que e sorteado a cada partida — degraus e cantos da matriz nascem em codigo,
em scripts/fase_03.gd, a partir de scripts/sorteio_arena.gd. Essa divisao e o coracao do
sorteio de layout: a silhueta da sala fica estavel para o jogador se orientar, e o que
muda e a rota e o significado de cada canto.

── Por que a validacao NAO esta aqui ─────────────────────────────────────────────────
Nas Fases 1 e 2 o validador de geometria roda neste ponto, antes de gravar o .tscn. Aqui
ele nao serviria de nada: a geometria que importa so existe em tempo de execucao. Ele
mudou de lugar e vive em sorteio_arena.gd, que sorteia, confere e RE-SORTEIA se reprovar.
O que este script garante e so que a casca bate com as constantes que o sorteador usa —
ver checar_coerencia() no fim do arquivo.
"""

from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "scenes" / "level" / "fase_03.tscn"

# geometria (copia do sorteio)
#
# Estes numeros sao COPIA de scripts/sorteio_arena.gd. Se mudarem la, mudam aqui — e
# checar_coerencia() falha se alguem mexer num sem mexer no outro.
LARGURA = 640
ALTURA = 208

Y_CHAO = 192
Y_PEDESTAL = 160
Y_DEGRAU = 136
Y_MEZANINO = 104

MEZANINO_ESQ = (96, 112)     # (x inicial, largura)
MEZANINO_DIR = (432, 112)
PEDESTAL_ESQ = (40, 96)
PEDESTAL_DIR = (504, 96)

ALTURA_PEDESTAL = 32
ESPESSURA_PLATAFORMA = 16

# O Chefe fica fora de alcance de proposito: o jogador nao tem verbo para machucar
# ninguem, e deixa-lo alcancavel criaria a expectativa frustrada de que da para revidar.
CHEFE_POS = (320, 56)

JOGADOR_POS = (320, 176)

# Janelas na parede do fundo, por onde a cidade do parallax aparece. (x, y) do canto.
JANELAS = [(168, 40), (248, 40), (392, 40), (472, 40)]
JANELA_LARGURA = 48
JANELA_ALTURA = 40


def cor(hexa: str, alfa: float = 1.0) -> str:
    """'rrggbb' -> literal Color(r, g, b, a) do formato .tscn."""
    r = int(hexa[0:2], 16) / 255.0
    g = int(hexa[2:4], 16) / 255.0
    b = int(hexa[4:6], 16) / 255.0
    return f"Color({r:.6f}, {g:.6f}, {b:.6f}, {alfa})"


def retangulo(w: float, h: float) -> str:
    """Poligono de um retangulo centrado na origem."""
    x, y = w / 2.0, h / 2.0
    return f"PackedVector2Array({-x}, {-y}, {x}, {-y}, {x}, {y}, {-x}, {y})"


def gerar() -> str:
    formas: list[tuple[str, float, float]] = []

    def forma(w: int, h: int) -> str:
        nome = f"Shape_{w}x{h}"
        if (nome, w, h) not in formas:
            formas.append((nome, w, h))
        return nome

    corpo: list[str] = []
    a = corpo.append

    # raiz e parallax
    a('[node name="Fase03" type="Node2D"]')
    a('script = ExtResource("script_fase")\n')

    a('[node name="Parallax" type="ParallaxBackground" parent="."]')
    a("layer = -3\n")
    a('[node name="Ceu" type="ParallaxLayer" parent="Parallax"]')
    a("motion_scale = Vector2(0, 0)\n")
    a('[node name="Fundo" type="ColorRect" parent="Parallax/Ceu"]')
    a("offset_right = 640.0")
    a("offset_bottom = 208.0")
    # Ceu de fim de tarde, e não quase-preto: a primeira captura tinha um fundo escuro
    # demais e a cidade sumia dentro da janela. A silhueta dos prédios só lê se houver
    # contraste atrás dela — e o expediente do Dia 3 termina ao anoitecer, então um tom
    # de entardecer é o que a fase pede de qualquer jeito.
    a(f"color = {cor('3a4260')}\n")

    # Duas camadas de cidade com velocidades diferentes: e o que da profundidade real a
    # uma arena que rola pouco na horizontal.
    #
    # motion_mirroring TEM de ser a largura real da textura. Na Fase 2 isto foi escrito
    # como um numero redondo maior que a arte e o espelhamento deixou buraco — o mesmo
    # defeito apareceria aqui, e desta vez emoldurado por uma janela.
    for nome, escala, largura, y, alfa, recurso in [
        ("Cidade", 0.2, 213, 62, 0.75, "tex_predios_longe"),
        ("Predios", 0.45, 272, 66, 1.0, "tex_predios"),
    ]:
        a(f'[node name="{nome}" type="ParallaxLayer" parent="Parallax"]')
        a(f"motion_scale = Vector2({escala}, 0)")
        a(f"motion_mirroring = Vector2({largura}, 0)\n")
        a(f'[node name="Arte" type="Sprite2D" parent="Parallax/{nome}"]')
        a(f"modulate = {cor('ffffff', alfa)}")
        a(f"position = Vector2({largura // 2}, {y})")
        a(f'texture = ExtResource("{recurso}")\n')

    # a sala
    a('[node name="Sala" type="Node2D" parent="."]')
    a("z_index = -2\n")

    # A parede e desenhada EM VOLTA das janelas, em faixas.
    #
    # Nao adianta desenhar a parede inteira e por um poligono transparente onde fica a
    # janela: poligono transparente nao abre buraco nenhum, so nao desenha nada, e a
    # parede continua tapando o parallax. A sala sai de fundo chapado, sem cidade.
    # Buraco em 2D se faz NAO PINTANDO, nao pintando por cima.
    faixa_janela_topo = min(jy for _, jy in JANELAS)
    faixa_janela_base = faixa_janela_topo + JANELA_ALTURA

    def parede(nome: str, x0: float, y0: float, x1: float, y1: float) -> None:
        if x1 - x0 <= 0 or y1 - y0 <= 0:
            return
        a(f'[node name="{nome}" type="Polygon2D" parent="Sala"]')
        a(f"color = {cor('2e2a33')}")
        a(f"position = Vector2({(x0 + x1) / 2}, {(y0 + y1) / 2})")
        a(f"polygon = {retangulo(x1 - x0, y1 - y0)}\n")

    parede("ParedeTopo", 0, 0, LARGURA, faixa_janela_topo)
    parede("ParedeBase", 0, faixa_janela_base, LARGURA, Y_CHAO)

    # Colunas de parede entre as janelas.
    cortes = sorted([(jx, jx + JANELA_LARGURA) for jx, _ in JANELAS])
    borda = 0
    for i, (j0, j1) in enumerate(cortes):
        parede(f"ParedeVao{i}", borda, faixa_janela_topo, j0, faixa_janela_base)
        borda = j1
    parede("ParedeVaoFim", borda, faixa_janela_topo, LARGURA, faixa_janela_base)

    # Caixilho: so a moldura, desenhada como quatro barras finas em volta do vao. Um
    # retangulo cheio atras da janela voltaria a tapar a cidade.
    for i, (jx, jy) in enumerate(JANELAS):
        for lado, (bx, by, bw, bh) in {
            "Esq": (jx - 2, jy + JANELA_ALTURA / 2, 4, JANELA_ALTURA + 4),
            "Dir": (jx + JANELA_LARGURA + 2, jy + JANELA_ALTURA / 2, 4, JANELA_ALTURA + 4),
            "Topo": (jx + JANELA_LARGURA / 2, jy - 2, JANELA_LARGURA + 4, 4),
            "Base": (jx + JANELA_LARGURA / 2, jy + JANELA_ALTURA + 2, JANELA_LARGURA + 4, 4),
        }.items():
            a(f'[node name="Caixilho{i}{lado}" type="Polygon2D" parent="Sala"]')
            a(f"position = Vector2({bx}, {by})")
            a(f"color = {cor('4a4453')}")
            a(f"polygon = {retangulo(bw, bh)}\n")

        # Travessa central: sem ela o vao le como buraco na parede, e nao como janela.
        a(f'[node name="Travessa{i}" type="Polygon2D" parent="Sala"]')
        a(f"position = Vector2({jx + JANELA_LARGURA / 2}, {jy + JANELA_ALTURA / 2})")
        a(f"color = {cor('4a4453')}")
        a(f"polygon = {retangulo(3, JANELA_ALTURA)}\n")

    # Quadros na parede, para a sala nao ficar chapada. Ficam ABAIXO da faixa do HUD,
    # LONGE das janelas e FORA do miolo da arena: retangulo claro na altura de um salto
    # le como plataforma flutuante, e o cenario nao cumpre a promessa.
    for i, (qx, qy, qw, qh) in enumerate([(64, 100, 22, 16), (576, 100, 22, 16)]):
        a(f'[node name="Quadro{i}" type="Polygon2D" parent="Sala"]')
        a(f"position = Vector2({qx}, {qy})")
        a(f"color = {cor('6a5f4e')}")
        a(f"polygon = {retangulo(qw, qh)}\n")
        a(f'[node name="Quadro{i}Tela" type="Polygon2D" parent="Sala"]')
        a(f"position = Vector2({qx}, {qy})")
        a(f"color = {cor('8d9bb0')}")
        a(f"polygon = {retangulo(qw - 6, qh - 6)}\n")

    a('[node name="Rodape" type="Polygon2D" parent="Sala"]')
    a(f"color = {cor('3b3541')}")
    a(f"position = Vector2({LARGURA // 2}, {Y_CHAO - 4})")
    a(f"polygon = {retangulo(LARGURA, 8)}\n")

    # Podio do Chefe. SEM colisao de proposito: ele precisa ler como apoiado em alguma
    # coisa (na primeira captura ele flutuava no meio do nada), mas dar colisao criaria
    # uma plataforma no centro do teto, e a conta mostra que ela seria alcancavel a partir
    # do mezanino — o que quebraria a premissa de que o Chefe e inalcancavel.
    a('[node name="Podio" type="Polygon2D" parent="Sala"]')
    a(f"position = Vector2({CHEFE_POS[0]}, {CHEFE_POS[1] + 26})")
    a(f"color = {cor('43323a')}")
    a(f"polygon = {retangulo(72, 10)}\n")
    a('[node name="PodioTopo" type="Polygon2D" parent="Sala"]')
    a(f"position = Vector2({CHEFE_POS[0]}, {CHEFE_POS[1] + 22})")
    a(f"color = {cor('6b4f59')}")
    a(f"polygon = {retangulo(80, 4)}\n")
    # Duas hastes ligando o podio ao teto: sem elas o podio tambem flutua, e o problema
    # so desce um nivel em vez de ser resolvido.
    for lado, hx in [("Esq", -30), ("Dir", 30)]:
        a(f'[node name="Haste{lado}" type="Polygon2D" parent="Sala"]')
        a(f"position = Vector2({CHEFE_POS[0] + hx}, {(CHEFE_POS[1] + 20) / 2})")
        a(f"color = {cor('43323a')}")
        a(f"polygon = {retangulo(3, CHEFE_POS[1] + 20)}\n")

    # superficies
    a('[node name="Colisores" type="Node2D" parent="."]\n')

    def plataforma(nome: str, cx: float, cy: float, w: int, h: int) -> None:
        a(f'[node name="{nome}" type="StaticBody2D" parent="Colisores"]')
        a(f"position = Vector2({cx}, {cy})\n")
        a(f'[node name="CollisionShape2D" type="CollisionShape2D" parent="Colisores/{nome}"]')
        a(f'shape = SubResource("{forma(w, h)}")\n')

    # Piso: 32px de espessura, superficie em Y_CHAO.
    plataforma("Piso", LARGURA / 2, Y_CHAO + 16, LARGURA, 32)

    for nome, (px, pw) in [("PedestalEsq", PEDESTAL_ESQ), ("PedestalDir", PEDESTAL_DIR)]:
        plataforma(nome, px + pw / 2, Y_PEDESTAL + ALTURA_PEDESTAL / 2, pw, ALTURA_PEDESTAL)

    for nome, (px, pw) in [("MezaninoEsq", MEZANINO_ESQ), ("MezaninoDir", MEZANINO_DIR)]:
        plataforma(nome, px + pw / 2, Y_MEZANINO + ESPESSURA_PLATAFORMA / 2, pw,
                   ESPESSURA_PLATAFORMA)

    # Paredes laterais: a arena e fechada. Sem elas o jogador sai andando da sala e cai no
    # poco de queda pela borda, o que leria como bug e nao como punicao.
    plataforma("ParedeEsq", -8, ALTURA / 2, 16, ALTURA + 64)
    plataforma("ParedeDir", LARGURA + 8, ALTURA / 2, 16, ALTURA + 64)

    # visual das superficies
    a('[node name="Superficies" type="Node2D" parent="."]')
    a("z_index = -1\n")

    def visual(nome: str, cx: float, cy: float, w: int, h: int, base: str, topo: str) -> None:
        a(f'[node name="{nome}" type="Polygon2D" parent="Superficies"]')
        a(f"position = Vector2({cx}, {cy})")
        a(f"color = {cor(base)}")
        a(f"polygon = {retangulo(w, h)}\n")
        a(f'[node name="{nome}Topo" type="Polygon2D" parent="Superficies"]')
        a(f"position = Vector2({cx}, {cy - h / 2 + 2})")
        a(f"color = {cor(topo)}")
        a(f"polygon = {retangulo(w, 4)}\n")

    visual("Piso", LARGURA / 2, Y_CHAO + 16, LARGURA, 32, "4a4038", "6f6152")
    for nome, (px, pw) in [("PedEsq", PEDESTAL_ESQ), ("PedDir", PEDESTAL_DIR)]:
        visual(nome, px + pw / 2, Y_PEDESTAL + ALTURA_PEDESTAL / 2, pw, ALTURA_PEDESTAL,
               "5c5142", "8a7a63")
    for nome, (px, pw) in [("MezEsq", MEZANINO_ESQ), ("MezDir", MEZANINO_DIR)]:
        visual(nome, px + pw / 2, Y_MEZANINO + ESPESSURA_PLATAFORMA / 2, pw,
               ESPESSURA_PLATAFORMA, "5c5142", "8a7a63")

    # o piche
    #
    # Ancorado no CANTO SUPERIOR (position fica no topo da pilha) para que fase_03.gd
    # possa so mover o y e escalar o corpo. Um poligono centrado exigiria mexer nos dois
    # ao mesmo tempo e as duas contas divergiriam no primeiro ajuste.
    a('[node name="Piche" type="Polygon2D" parent="."]')
    a("z_index = 2")
    a("visible = false")
    a(f"position = Vector2(0, {Y_CHAO})")
    a(f"color = {cor('3a2c1e')}")
    a(f"polygon = PackedVector2Array(0, 0, {LARGURA}, 0, {LARGURA}, 8, 0, 8)\n")

    # nos que a base exige
    a('[node name="Zonas" type="Node2D" parent="."]\n')
    a('[node name="Tarefas" type="Node2D" parent="."]\n')
    a('[node name="Bifurcacoes" type="Node2D" parent="."]\n')

    a('[node name="Checkpoints" type="Node2D" parent="."]\n')
    a('[node name="Checkpoint0" type="Area2D" parent="Checkpoints"]')
    a(f"position = Vector2({JOGADOR_POS[0]}, {JOGADOR_POS[1]})")
    a("collision_layer = 0")
    a("collision_mask = 2\n")
    a('[node name="CollisionShape2D" type="CollisionShape2D" parent="Checkpoints/Checkpoint0"]')
    a(f'shape = SubResource("{forma(24, 32)}")\n')

    a('[node name="Inimigos" type="Node2D" parent="."]\n')
    a('[node name="Chefe" parent="Inimigos" instance=ExtResource("cena_chefe")]')
    a(f"position = Vector2({CHEFE_POS[0]}, {CHEFE_POS[1]})\n")

    # A saida e decorativa nesta fase: nao ha cota de urgentes e vencer e sobreviver ao
    # expediente. Ela existe porque fase_base.gd le a posicao dela para desenhar a barra
    # de percurso do HUD, e porque a porta da sala precisa estar em algum lugar.
    a('[node name="Saida" parent="." instance=ExtResource("cena_saida")]')
    a(f"position = Vector2({LARGURA - 16}, {Y_CHAO})\n")

    a('[node name="ZonaDeQueda" type="Area2D" parent="."]')
    a(f"position = Vector2({LARGURA // 2}, {ALTURA + 90})")
    a("collision_layer = 0")
    a("collision_mask = 2\n")
    a('[node name="CollisionShape2D" type="CollisionShape2D" parent="ZonaDeQueda"]')
    a(f'shape = SubResource("{forma(LARGURA + 200, 40)}")\n')

    # A camera fica travada: a arena tem 640px de largura e 208 de altura, e a altura e
    # exatamente a do viewport. Numa luta de chefao, nao ver o teto e injusto.
    a('[node name="Camera" parent="." instance=ExtResource("cena_camera")]')
    a(f"position = Vector2({LARGURA // 2}, {ALTURA // 2})")
    a("limit_left = 0")
    a("limit_top = 0")
    a(f"limit_right = {LARGURA}")
    a(f"limit_bottom = {ALTURA}\n")

    a('[node name="Player" parent="." instance=ExtResource("cena_player")]')
    a(f"position = Vector2({JOGADOR_POS[0]}, {JOGADOR_POS[1]})\n")

    a('[node name="HUD" parent="." instance=ExtResource("cena_hud")]\n')

    # cabecalho
    recursos = [
        ('Script', 'res://scripts/fase_03.gd', 'script_fase'),
        ('PackedScene', 'res://scenes/level/camera.tscn', 'cena_camera'),
        ('PackedScene', 'res://scenes/player/player.tscn', 'cena_player'),
        ('PackedScene', 'res://scenes/ui/hud.tscn', 'cena_hud'),
        ('PackedScene', 'res://scenes/tasks/saida.tscn', 'cena_saida'),
        ('PackedScene', 'res://entities/chefe.tscn', 'cena_chefe'),
        ('Texture2D', 'res://sprites/Parallax Industrial/far-buildings.png',
         'tex_predios_longe'),
        ('Texture2D', 'res://sprites/Parallax Industrial/buildings.png', 'tex_predios'),
    ]

    cabecalho = [f"[gd_scene load_steps={len(recursos) + len(formas) + 1} format=3]\n"]
    for tipo, caminho, ident in recursos:
        cabecalho.append(f'[ext_resource type="{tipo}" path="{caminho}" id="{ident}"]')
    cabecalho.append("")
    for nome, w, h in formas:
        cabecalho.append(f'[sub_resource type="RectangleShape2D" id="{nome}"]')
        cabecalho.append(f"size = Vector2({w}, {h})\n")

    return "\n".join(cabecalho) + "\n" + "\n".join(corpo)


def checar_coerencia() -> list[str]:
    """Confere que a casca estatica bate com o que o sorteador espera.

    O sorteador posiciona cantos sobre PEDESTAL_* e MEZANINO_*, e mede alturas de pulo
    entre Y_CHAO, Y_PEDESTAL, Y_DEGRAU e Y_MEZANINO. Se a casca e o sorteio discordarem,
    os cantos nascem no ar e a fase fica invencivel sem nada denunciar — este e o unico
    jeito de o Python continuar protegendo alguma coisa depois que a validacao de
    geometria mudou para dentro do jogo.
    """
    fonte = (RAIZ / "scripts" / "sorteio_arena.gd").read_text(encoding="utf-8")
    erros = []

    esperado = {
        "Y_CHAO": Y_CHAO,
        "Y_PEDESTAL": Y_PEDESTAL,
        "Y_DEGRAU": Y_DEGRAU,
        "Y_MEZANINO": Y_MEZANINO,
        "LARGURA": LARGURA,
        "ALTURA": ALTURA,
    }
    for nome, valor in esperado.items():
        marca = f"const {nome} := {valor}."
        if marca not in fonte:
            erros.append(f"{nome} = {valor} nao bate com sorteio_arena.gd")

    for nome, (px, pw) in [("MEZANINO_ESQ", MEZANINO_ESQ), ("MEZANINO_DIR", MEZANINO_DIR)]:
        if f"const {nome} := Rect2({px}, Y_MEZANINO, {pw}, 16)" not in fonte:
            erros.append(f"{nome} divergente entre casca e sorteio")
    for nome, (px, pw) in [("PEDESTAL_ESQ", PEDESTAL_ESQ), ("PEDESTAL_DIR", PEDESTAL_DIR)]:
        if f"const {nome} := Rect2({px}, Y_PEDESTAL, {pw}, 32)" not in fonte:
            erros.append(f"{nome} divergente entre casca e sorteio")

    # Nenhuma janela pode ficar atras de uma plataforma: e o defeito que ja apareceu duas
    # vezes neste projeto e que virou assercao de teste na Fase 1.
    for jx, jy in JANELAS:
        j0, j1 = jx, jx + JANELA_LARGURA
        for px, pw in [MEZANINO_ESQ, MEZANINO_DIR]:
            p0, p1 = px, px + pw
            sobrepoe_x = j0 < p1 and p0 < j1
            sobrepoe_y = jy < Y_MEZANINO + ESPESSURA_PLATAFORMA and Y_MEZANINO < jy + JANELA_ALTURA
            if sobrepoe_x and sobrepoe_y:
                erros.append(f"janela em ({jx},{jy}) atras de plataforma em {px}")

    return erros


if __name__ == "__main__":
    problemas = checar_coerencia()
    if problemas:
        print("RECUSADO — a casca nao bate com o sorteador:")
        for p in problemas:
            print("  -", p)
        raise SystemExit(1)

    SAIDA.write_text(gerar(), encoding="utf-8")
    print(f"escrito: {SAIDA.relative_to(RAIZ)}")
