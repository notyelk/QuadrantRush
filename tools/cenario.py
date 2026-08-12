"""Ferramentas de leitura/escrita do cenario da fase (TileMapLayer de fase_01.tscn).

Por que isto existe: fase_01.tscn tem 164 colunas e cerca de mil celulas pintadas.
Editar isso a mao no .tscn e inviavel, e a sessao anterior perdeu o gerador porque ele
ficou fora do repositorio. Este arquivo fica versionado de proposito.

Formato do tile_map_data (confirmado por round-trip com o proprio Godot):
    2 bytes zerados de cabecalho, depois 12 bytes por celula --
    col, row, source_id, atlas_x, atlas_y, alternative -- todos int16 little-endian.
Celulas repetidas sao permitidas: vale a ULTIMA do array. Foi exatamente isso que
causou o bug visual dos moveis (objeto sobrescrevendo o tile de parede na mesma camada).

Uso:
    python tools/cenario.py            # relatorio do que esta pintado hoje
"""

from __future__ import annotations

import base64
import collections
import os
import re
import struct

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FASE = os.path.join(RAIZ, "scenes", "level", "fase_01.tscn")

TAMANHO_TILE = 16

PADRAO_CAMADA = (
    r'(\[node name="%s" type="TileMapLayer".*?\ntile_map_data = PackedByteArray\(")([^"]*)("\))'
)


def decodificar(b64: str) -> list[tuple[int, int, int, int, int, int]]:
    bruto = base64.b64decode(b64)
    if (len(bruto) - 2) % 12 != 0:
        raise ValueError("tile_map_data com tamanho inesperado: %d bytes" % len(bruto))
    return [
        struct.unpack_from("<6h", bruto, i) for i in range(2, len(bruto), 12)
    ]


def codificar(celulas) -> str:
    bruto = b"\x00\x00" + b"".join(struct.pack("<6h", *c) for c in celulas)
    return base64.b64encode(bruto).decode()


def ler_camada(nome: str, texto: str) -> list[tuple[int, int, int, int, int, int]]:
    achado = re.search(PADRAO_CAMADA % re.escape(nome), texto, re.S)
    if not achado:
        raise KeyError("camada %r nao encontrada em %s" % (nome, FASE))
    return decodificar(achado.group(2))


def gravar_camada(nome: str, celulas, texto: str) -> str:
    novo = codificar(celulas)
    return re.sub(
        PADRAO_CAMADA % re.escape(nome),
        lambda m: m.group(1) + novo + m.group(3),
        texto,
        count=1,
        flags=re.S,
    )


def resolver(celulas) -> dict[tuple[int, int], tuple[int, int, int, int, int, int]]:
    """Aplica a regra 'vale a ultima' e devolve o mapa final celula -> registro."""
    final = {}
    for c in celulas:
        final[(c[0], c[1])] = c
    return final


def relatorio() -> None:
    texto = open(FASE, encoding="utf-8").read()
    for nome in ("Decoracao", "Objetos", "Piso"):
        try:
            celulas = ler_camada(nome, texto)
        except KeyError:
            print("== %s: (nao existe)" % nome)
            continue
        posicoes = collections.Counter((c[0], c[1]) for c in celulas)
        repetidas = [p for p, n in posicoes.items() if n > 1]
        print("== %s: %d celulas, %d sobrescritas" % (nome, len(celulas), len(repetidas)))
        fontes = collections.Counter(c[2] for c in celulas)
        for src, n in sorted(fontes.items()):
            linhas = sorted({c[1] for c in celulas if c[2] == src})
            print("     source %-3d %4d celulas  linhas=%s" % (src, n, linhas))


if __name__ == "__main__":
    relatorio()
