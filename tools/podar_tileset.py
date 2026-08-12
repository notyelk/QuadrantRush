"""Remove do TileSet do escritorio as fontes de atlas que nenhuma fase pinta.

Por que isto existe: escritorio.tres nasceu com 25 fontes de atlas, de cinco packs de
arte diferentes, registradas "por garantia". Medindo o tile_map_data das fases, so tres
delas (as do Little Bits Office) tem uma unica celula pintada. As outras 22 nao aparecem
no jogo e ainda assim arrastam os arquivos de imagem para dentro do export publico da
Etapa 9 -- inclusive dois packs cuja licenca nunca foi localizada.

Fica versionado porque a decisao de quais fontes ficaram precisa ser auditavel, e porque
o mesmo teste vale toda vez que um pack novo entrar no projeto.

Uso:
    python tools/podar_tileset.py          # mostra o que faria
    python tools/podar_tileset.py --gravar # grava
"""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cenario  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILESET = os.path.join(RAIZ, "scenes", "tiles", "escritorio.tres")
FASES = ["fase_01", "fase_02"]


def fontes_usadas() -> set[int]:
    """Quais source_id aparecem de fato no tile_map_data de alguma fase."""
    usadas = set()
    for fase in FASES:
        caminho = os.path.join(RAIZ, "scenes", "level", "%s.tscn" % fase)
        texto = open(caminho, encoding="utf-8").read()
        for nome in re.findall(r'\[node name="([^"]+)" type="TileMapLayer"', texto):
            for celula in cenario.ler_camada(nome, texto):
                usadas.add(celula[2])
    return usadas


def podar(texto: str, manter: set[int]) -> tuple[str, list[str]]:
    # 1. Quais sub-recursos correspondem as fontes que ficam.
    mapa = dict(re.findall(r'sources/(\d+) = SubResource\("([^"]+)"\)', texto))
    subs_mantidos = {sub for sid, sub in mapa.items() if int(sid) in manter}

    removidos = []

    # 2. Fora os blocos [sub_resource] das fontes que saem, com tudo o que vem depois
    #    deles ate o proximo cabecalho.
    def talvez_remover(m: re.Match) -> str:
        if m.group(1) in subs_mantidos:
            return m.group(0)
        return ""

    texto = re.sub(
        r'\[sub_resource type="TileSetAtlasSource" id="([^"]+)"\].*?(?=\n\[|\Z)',
        talvez_remover,
        texto,
        flags=re.S,
    )

    # 3. Fora as linhas sources/N das fontes que sairam.
    texto = re.sub(
        r'^sources/(\d+) = SubResource\("[^"]+"\)\n?',
        lambda m: m.group(0) if int(m.group(1)) in manter else "",
        texto,
        flags=re.M,
    )

    # 4. Fora os ext_resource de textura que ninguem mais referencia.
    for caminho, ident in re.findall(
        r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', texto
    ):
        if len(re.findall(r'ExtResource\("%s"\)' % re.escape(ident), texto)) == 0:
            texto = re.sub(
                r'\[ext_resource type="Texture2D" path="[^"]*" id="%s"\]\n?'
                % re.escape(ident),
                "",
                texto,
            )
            removidos.append(caminho)

    # 5. load_steps volta a bater com o numero de dependencias declaradas.
    passos = len(re.findall(r"^\[ext_resource ", texto, re.M))
    passos += len(re.findall(r"^\[sub_resource ", texto, re.M))
    texto = re.sub(r"load_steps=\d+", "load_steps=%d" % (passos + 1), texto, count=1)

    # 6. Linhas em branco duplicadas deixadas pelas remocoes.
    texto = re.sub(r"\n{3,}", "\n\n", texto)

    return texto, removidos


def main() -> None:
    manter = fontes_usadas()
    texto = open(TILESET, encoding="utf-8").read()
    antes = len(re.findall(r"^sources/\d+ = ", texto, re.M))

    novo, removidos = podar(texto, manter)
    depois = len(re.findall(r"^sources/\d+ = ", novo, re.M))

    print("fontes pintadas por alguma fase: %s" % sorted(manter))
    print("fontes no TileSet: %d -> %d" % (antes, depois))
    print("texturas que deixam de ser dependencia (%d):" % len(removidos))
    for caminho in sorted(removidos):
        print("   ", caminho)

    if "--gravar" in sys.argv:
        open(TILESET, "w", encoding="utf-8", newline="\n").write(novo)
        print("\ngravado em", TILESET)
    else:
        print("\n(simulacao -- rode com --gravar para aplicar)")


if __name__ == "__main__":
    main()
