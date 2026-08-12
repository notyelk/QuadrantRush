# Créditos e licenças dos recursos

Este arquivo lista a procedência de tudo o que o jogo usa e não foi escrito neste
repositório. Ele existe por causa da **Etapa 9** (publicação com export web e código-fonte
público): antes de publicar é preciso saber que cada arquivo pode ser publicado.

O código-fonte está sob a licença em [`LICENSE`](LICENSE). O que está abaixo não é código.

---

## Arte

| Recurso | Autor | Licença | Onde aparece |
|---|---|---|---|
| **Little Bits: Office** — tiles de chão, parede e mobília; personagem `businessman1` | AdricCustoms ([itch.io](https://adriccustoms.itch.io/little-bits-office)) | Uso livre declarado pelo autor na página do pack ("use it for whatever you like") | Todo o cenário e o personagem dos Dias 1 e 2 |
| **PixelOffice** | 2dPig | CC0 1.0 (`LICENSE.txt` no pacote) | Ícone de papel das tarefas, elementos de fundo do Dia 1 |
| **Sprite Pack 5** (Grizzly, Moe Scotty, Big Red) | GrafxKid | CC0 1.0 (`LICENSE.txt` no pacote) | "O Prazo" (urso) e o ladrão de tempo do Dia 1; o Chefe do Dia 3 |
| **Parallax Industrial** | Luis Zuno (Ansimuz) | CC0 1.0 (`LICENSE.pdf` no pacote) | Cidade vista pelas janelas, em três camadas de parallax |

O halo em `sprites/gerado/` é desenhado pelo próprio projeto, e não vem de pack nenhum.

**CC0** dispensa atribuição. Os autores estão creditados aqui mesmo assim — é cortesia
barata, e é o que permite a quem for auditar o trabalho verificar a procedência sem
precisar procurar.

O único item que **não** tem licença formal escrita é o Little Bits: Office; a permissão é
uma declaração pública do autor na página do pack. Ele é o pack mais usado do projeto, e
por isso o crédito acima é nominal e com link.

### O que foi removido do repositório, e por quê

A regra aqui é simples: **o que o jogo não usa não fica versionado**. Arquivo que ninguém
referencia ainda entra no export da Etapa 9, engorda o download e — pior — obriga a
auditar a licença de algo que nem aparece na tela.

Packs de escritório que chegaram a ser registrados no `TileSet` sem que uma única célula
fosse pintada com eles:

- **Desk Essentials** — licença não localizada no pacote. Nunca usado.
- **Office Assets** — licença não localizada no pacote. Nunca usado.
- **Free Office Pixel Art** (arlantr) — uso livre declarado, mas também nunca usado.
- **Seasonal Tilesets**, **Sprite Pack 6** e **Office Space Tileset** — usados apenas por
  uma versão anterior do Dia 3, que se passava numa floresta e foi descartada.

A verificação foi feita medindo o `tile_map_data` real das fases
(`python tools/podar_tileset.py`), e não por inspeção visual: das 25 fontes de atlas do
`scenes/tiles/escritorio.tres`, só três tinham tiles pintados.

Depois disso a mesma medida foi aplicada aos arquivos soltos: sprites e efeitos sonoros
sem uma única referência em cena ou script saíram também — entre eles o pack Robo Retro
inteiro (o personagem jogável passou a ser o `businessman1`), os personagens do Sprite
Pack 5 que nunca entraram no jogo e as seis direções de caminhada que a arte lateral não
precisa, já que o espelhamento resolve.

## Áudio

Todos os 20 efeitos e as 2 camadas de trilha em `audio/` são **sintetizados pelo próprio
projeto**, por `tools/audio_gen.py`. Não há gravação de terceiro no jogo, e portanto não há
licença de áudio a conferir antes de publicar. Foi decisão de projeto, exatamente para
evitar esta fila de verificação.

## Motor e bibliotecas

- **Godot Engine 4.6** — MIT. Os binários do export web incluem o runtime da engine, sob a
  mesma licença; o arquivo de licença é gerado pelo próprio Godot no export.
- Nenhum plugin ou addon. O acesso ao Supabase é feito com o nó `HTTPRequest` da engine,
  conforme a seção 3.1 da Metodologia do TCC.
