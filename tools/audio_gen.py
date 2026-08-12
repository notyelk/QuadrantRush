"""Sintetiza todos os efeitos sonoros e a trilha da Fase 1.

Por que sintetizar em vez de baixar um pack:

1. **Licença resolvida na origem.** O TCC vai ser publicado (Etapa 9, export WebGL
   em hospedagem pública) e o repositório é público. Áudio gerado por este script é
   obra do próprio projeto — não há autor de terceiros para creditar, nem licença
   para conferir antes de exportar. Vários packs de arte já em `sprites/` estão com
   licença "não localizada"; áudio não vai entrar nessa fila.
2. **Coerência.** Um pack de sons tem timbres de origens diferentes. Aqui os quinze
   efeitos saem das mesmas três formas de onda e da mesma paleta de frequências, e
   a música usa a mesma escala dos efeitos de acerto/erro. O conjunto soa como um
   jogo só.
3. **Ajustável.** Se o pulo ficar agudo demais no playtest, muda um número aqui e
   roda de novo — não precisa procurar outro arquivo em outro site.

Como rodar (da raiz do projeto):

    python tools/audio_gen.py

Sai em `audio/sfx/*.wav` e `audio/musica/*.wav`, 22050 Hz, 16 bits, mono. 22050 é
metade da taxa de CD: para chiptune é indistinguível e corta o tamanho do export
WebGL pela metade, que importa numa hospedagem gratuita.

A trilha tem DUAS camadas do mesmo comprimento e do mesmo andamento, feitas para
tocar em sincronia: `expediente` (base) e `perseguicao` (bateria e baixo tensos).
O jogo mantém as duas rodando e só muda o volume da segunda conforme o urso se
aproxima — é remixagem vertical, a mesma técnica que jogos de ação usam para a
música reagir ao perigo sem cortar nem recomeçar nada.
"""

from __future__ import annotations

import math
import os
import struct
import wave

import numpy as np

TAXA = 22050
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PASTA_SFX = os.path.join(RAIZ, "audio", "sfx")
PASTA_MUSICA = os.path.join(RAIZ, "audio", "musica")

rng = np.random.default_rng(20260807)


# osciladores


def _t(dur: float) -> np.ndarray:
    return np.arange(int(TAXA * dur)) / TAXA


def quadrada(freq, dur: float, duty: float = 0.5) -> np.ndarray:
    """Onda quadrada. É o timbre básico do chiptune: agressiva e barata.

    `freq` aceita um número ou um array do mesmo tamanho do trecho, o que permite
    varreduras (o pulo, o rugido) com a mesma função.
    """
    t = _t(dur)
    fase = np.cumsum(np.broadcast_to(np.asarray(freq, dtype=float), t.shape)) / TAXA
    return np.where((fase % 1.0) < duty, 1.0, -1.0)


def triangular(freq, dur: float) -> np.ndarray:
    """Mais doce que a quadrada. Usada onde o som precisa agradar (coleta, chime)."""
    t = _t(dur)
    fase = np.cumsum(np.broadcast_to(np.asarray(freq, dtype=float), t.shape)) / TAXA
    return 2.0 * np.abs(2.0 * (fase % 1.0) - 1.0) - 1.0


def serra(freq, dur: float) -> np.ndarray:
    """Rica em harmônicos — corpo de baixo e de rugido."""
    t = _t(dur)
    fase = np.cumsum(np.broadcast_to(np.asarray(freq, dtype=float), t.shape)) / TAXA
    return 2.0 * (fase % 1.0) - 1.0


def ruido(dur: float) -> np.ndarray:
    """Percussão, impacto, poeira, passo."""
    return rng.uniform(-1.0, 1.0, int(TAXA * dur))


def varredura(f0: float, f1: float, dur: float, curva: float = 1.0) -> np.ndarray:
    """Frequências de f0 a f1. curva > 1 concentra a mudança no fim."""
    x = np.linspace(0.0, 1.0, int(TAXA * dur)) ** curva
    return f0 + (f1 - f0) * x


# envelopes


def env(dur: float, ataque: float = 0.005, queda: float = 0.0,
        sustento: float = 1.0, solta: float = 0.05) -> np.ndarray:
    """ADSR. O ataque curto (5ms) evita o "clique" de ligar a onda no meio."""
    n = int(TAXA * dur)
    na = max(int(TAXA * ataque), 1)
    nq = int(TAXA * queda)
    ns = max(int(TAXA * solta), 1)
    nsus = max(n - na - nq - ns, 0)
    partes = [
        np.linspace(0.0, 1.0, na),
        np.linspace(1.0, sustento, nq) if nq else np.empty(0),
        np.full(nsus, sustento),
        np.linspace(sustento, 0.0, ns),
    ]
    e = np.concatenate(partes)
    return np.resize(e, n)


def decaimento(dur: float, forca: float = 12.0) -> np.ndarray:
    """Queda exponencial — o envelope natural de percussão e de bipe curto."""
    return np.exp(-forca * np.linspace(0.0, 1.0, int(TAXA * dur)))


def passa_baixa(sinal: np.ndarray, corte: float) -> np.ndarray:
    """Filtro de um polo. Tira o brilho do ruído e o transforma em som grave/abafado."""
    a = math.exp(-2.0 * math.pi * corte / TAXA)
    saida = np.empty_like(sinal)
    anterior = 0.0
    for i, amostra in enumerate(sinal):
        anterior = (1.0 - a) * amostra + a * anterior
        saida[i] = anterior
    return saida


def somar(*trechos: np.ndarray) -> np.ndarray:
    """Mistura trechos de tamanhos diferentes alinhados pelo início."""
    n = max(len(x) for x in trechos)
    saida = np.zeros(n)
    for x in trechos:
        saida[: len(x)] += x
    return saida


def emendar(*trechos: np.ndarray) -> np.ndarray:
    return np.concatenate(trechos)


def silencio(dur: float) -> np.ndarray:
    return np.zeros(int(TAXA * dur))


def normalizar(sinal: np.ndarray, pico: float = 0.85) -> np.ndarray:
    maximo = np.max(np.abs(sinal))
    if maximo < 1e-9:
        return sinal
    return sinal * (pico / maximo)


def gravar(caminho: str, sinal: np.ndarray) -> None:
    sinal = np.clip(sinal, -1.0, 1.0)
    dados = (sinal * 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with wave.open(caminho, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(TAXA)
        f.writeframes(dados.tobytes())
    print("  %-28s %6.2fs" % (os.path.basename(caminho), len(sinal) / TAXA))


# efeitos


def sfx_pulo() -> np.ndarray:
    # Varredura para cima: o ouvido lê subida de altura como subida no espaço.
    return quadrada(varredura(300, 780, 0.13, 0.6), 0.13, 0.35) * decaimento(0.13, 7.0) * 0.5


def sfx_pouso() -> np.ndarray:
    baque = passa_baixa(ruido(0.11), 900) * decaimento(0.11, 22.0) * 1.4
    corpo = quadrada(varredura(180, 70, 0.09), 0.09) * decaimento(0.09, 26.0) * 0.35
    return somar(baque, corpo)


def sfx_passo() -> np.ndarray:
    return passa_baixa(ruido(0.045), 1800) * decaimento(0.045, 40.0) * 0.5


def sfx_coleta() -> np.ndarray:
    """Arpejo maior ascendente — o formato universal de 'isso foi certo'."""
    notas = [523.25, 659.25, 783.99, 1046.50]  # dó maior, do dó ao dó
    return emendar(*[
        triangular(f, 0.055) * decaimento(0.055, 9.0) * 0.42 for f in notas
    ])


def sfx_coleta_bonus() -> np.ndarray:
    notas = [659.25, 830.61, 987.77, 1318.51, 1567.98]
    return emendar(*[
        triangular(f, 0.05) * decaimento(0.05, 8.0) * 0.42 for f in notas
    ])


def sfx_delegar() -> np.ndarray:
    """Duas notas em quinta: 'passei adiante', resolvido mas não conquistado."""
    a = triangular(587.33, 0.09) * decaimento(0.09, 8.0) * 0.4
    b = triangular(880.00, 0.16) * decaimento(0.16, 6.0) * 0.4
    return emendar(a, b)


def sfx_erro() -> np.ndarray:
    """Descendente e com batimento: duas ondas quase afinadas brigam e soam errado."""
    base = quadrada(varredura(320, 120, 0.26, 1.4), 0.26, 0.5)
    desafinada = quadrada(varredura(331, 124, 0.26, 1.4), 0.26, 0.5)
    return (base + desafinada) * decaimento(0.26, 5.0) * 0.28


def sfx_ignorou() -> np.ndarray:
    """Bipe grave e curto: registrou, não celebrou, não repreendeu."""
    return triangular(196.0, 0.1) * decaimento(0.1, 13.0) * 0.3


def sfx_dano() -> np.ndarray:
    aspero = ruido(0.2) * decaimento(0.2, 11.0) * 0.5
    queda = serra(varredura(420, 90, 0.2, 1.5), 0.2) * decaimento(0.2, 8.0) * 0.4
    return somar(aspero, queda)


def sfx_urso_rugido() -> np.ndarray:
    """Grave, longo e com vibrato lento — o telegrafo do bote precisa ser inconfundível."""
    dur = 0.55
    t = _t(dur)
    vibrato = 1.0 + 0.06 * np.sin(2 * math.pi * 7.0 * t)
    corpo = serra(varredura(95, 62, dur, 0.8) * vibrato, dur) * 0.55
    rosnado = passa_baixa(ruido(dur), 700) * 0.5
    return somar(corpo, rosnado) * env(dur, 0.04, 0.15, 0.75, 0.2)


def sfx_urso_passo() -> np.ndarray:
    return passa_baixa(ruido(0.13), 420) * decaimento(0.13, 17.0) * 1.5


def sfx_urso_acerto() -> np.ndarray:
    impacto = passa_baixa(ruido(0.3), 1300) * decaimento(0.3, 9.0) * 1.2
    grave = serra(varredura(160, 45, 0.3, 1.2), 0.3) * decaimento(0.3, 7.0) * 0.6
    return somar(impacto, grave)


def sfx_mosca() -> np.ndarray:
    """Zumbido curto do ladrão de tempo."""
    dur = 0.3
    t = _t(dur)
    tremulo = 220.0 + 30.0 * np.sin(2 * math.pi * 22.0 * t)
    return serra(tremulo, dur) * env(dur, 0.03, 0.0, 1.0, 0.12) * 0.24


def sfx_checkpoint() -> np.ndarray:
    a = triangular(783.99, 0.1) * decaimento(0.1, 7.0) * 0.35
    b = triangular(1174.66, 0.26) * decaimento(0.26, 4.5) * 0.35
    return emendar(a, b)


def sfx_porta() -> np.ndarray:
    """Trilho mecânico e depois o sino: a saída abriu."""
    trilho = passa_baixa(ruido(0.35), 2600) * env(0.35, 0.02, 0.1, 0.5, 0.15) * 0.3
    sino = emendar(
        silencio(0.3),
        triangular(1046.50, 0.35) * decaimento(0.35, 4.0) * 0.4,
    )
    return somar(trilho, sino)


def sfx_travado() -> np.ndarray:
    """Maçaneta que não gira — grave, seco, duas batidas."""
    batida = passa_baixa(ruido(0.07), 700) * decaimento(0.07, 30.0) * 1.1
    return emendar(batida, silencio(0.06), batida * 0.8)


def sfx_tique() -> np.ndarray:
    """Tique de relógio dos últimos segundos."""
    return passa_baixa(ruido(0.03), 3000) * decaimento(0.03, 60.0) * 0.5


def sfx_notificacao() -> np.ndarray:
    """A interrupcao da Fase 2. Duas notas agudas ascendentes, o formato de alerta de
    celular -- brilhante de proposito: ele PRECISA roubar a atencao, porque roubar a
    atencao e exatamente o que a mecanica faz."""
    a = quadrada(1318.51, 0.07, 0.5) * decaimento(0.07, 14.0) * 0.3
    b = quadrada(1760.0, 0.16, 0.5) * decaimento(0.16, 9.0) * 0.3
    return emendar(a, b)


def sfx_chegada() -> np.ndarray:
    """Papel descendo: ruido filtrado varrendo para baixo. Avisa que algo entrou em
    cena sem competir com o som da acao que o jogador vai tomar depois."""
    dur = 0.34
    sopro = passa_baixa(ruido(dur), 1800) * env(dur, 0.04, 0.0, 1.0, 0.2) * 0.22
    corpo = varredura(520.0, 240.0, dur, 1.6) * decaimento(dur, 5.0) * 0.1
    return somar(sopro, corpo)


def sfx_ui() -> np.ndarray:
    return quadrada(880.0, 0.045, 0.25) * decaimento(0.045, 20.0) * 0.25


def sfx_vitoria() -> np.ndarray:
    """Fanfarra maior. Dó–mi–sol–dó com a última sustentada e um brilho por cima."""
    notas = [(523.25, 0.13), (659.25, 0.13), (783.99, 0.13), (1046.50, 0.55)]
    linha = emendar(*[
        triangular(f, d) * env(d, 0.008, 0.05, 0.8, min(d * 0.5, 0.25)) * 0.4
        for f, d in notas
    ])
    brilho = emendar(
        silencio(0.39),
        triangular(1567.98, 0.55) * env(0.55, 0.02, 0.1, 0.6, 0.3) * 0.2,
    )
    return somar(linha, brilho)


def sfx_derrota() -> np.ndarray:
    """Descida cromática: o expediente acabou sem terminar o trabalho."""
    notas = [(392.00, 0.18), (349.23, 0.18), (311.13, 0.18), (261.63, 0.6)]
    return emendar(*[
        triangular(f, d) * env(d, 0.01, 0.06, 0.75, min(d * 0.5, 0.3)) * 0.4
        for f, d in notas
    ])


# caixa de saida


def sfx_comporta() -> np.ndarray:
    """A comporta Q2 abrindo -- o som mais recompensador da fase, e de proposito.

    Tem que valer o desvio: o jogador desceu na direcao do perigo para chegar aqui.
    Estrutura em tres tempos: a trava cedendo (impacto grave), o dreno abrindo
    (ruido varrendo para baixo, que e o piche indo embora) e o acorde de alivio.
    """
    trava = passa_baixa(ruido(0.09), 420) * decaimento(0.09, 22.0) * 0.85
    dreno = passa_baixa(ruido(0.55), 900) * env(0.55, 0.04, 0.35) * 0.5
    descida = varredura(520, 130, 0.55, 1.4) * env(0.55, 0.02, 0.4) * 0.3
    alivio = somar(
        triangular(261.63, 0.6) * decaimento(0.6, 4.0) * 0.4,
        triangular(392.00, 0.6) * decaimento(0.6, 4.0) * 0.32,
        triangular(523.25, 0.6) * decaimento(0.6, 4.5) * 0.26,
    )
    return emendar(trava, somar(dreno, descida), alivio)


def _acorde_do_passo(passo: int):
    return ACORDES[(passo // 16) % len(ACORDES)]


def _colocar(faixa: np.ndarray, passo: int, som: np.ndarray) -> None:
    i = int(passo * DUR_PASSO * TAXA)
    fim = min(i + len(som), len(faixa))
    if fim > i:
        faixa[i:fim] += som[: fim - i]


def _faixa_vazia() -> np.ndarray:
    return np.zeros(int(PASSOS * DUR_PASSO * TAXA) + TAXA // 2)


def _cortar_no_loop(faixa: np.ndarray) -> np.ndarray:
    """Dobra a cauda que passou do fim de volta no início.

    Sem isso, uma nota que soa no último passo é cortada no emendo do loop e dá um
    clique audível a cada volta. Dobrando, ela continua soando por cima do começo —
    que é exatamente o que aconteceria se a música seguisse tocando.
    """
    n = int(PASSOS * DUR_PASSO * TAXA)
    corpo = faixa[:n].copy()
    cauda = faixa[n:]
    corpo[: len(cauda)] += cauda
    return corpo


def musica_expediente() -> np.ndarray:
    baixo = _faixa_vazia()
    arpejo = _faixa_vazia()
    marcacao = _faixa_vazia()

    for passo in range(PASSOS):
        raiz, tríade = _acorde_do_passo(passo)

        # Baixo em colcheias alternando tônica e oitava: motor constante, o
        # equivalente sonoro de um relógio de ponto andando.
        if passo % 2 == 0:
            f = NOTA[raiz] * (2.0 if (passo // 2) % 4 == 3 else 1.0)
            _colocar(baixo, passo, serra(f, DUR_PASSO * 0.9)
                     * decaimento(DUR_PASSO * 0.9, 6.0) * 0.34)

        # Arpejo subindo e descendo pela tríade.
        indice = passo % 6
        grau = [0, 1, 2, 1, 2, 1][indice]
        f = NOTA[tríade[grau]] * 2.0
        _colocar(arpejo, passo, triangular(f, DUR_PASSO * 0.8)
                 * decaimento(DUR_PASSO * 0.8, 7.0) * 0.16)

        # Chimbal seco nos contratempos.
        if passo % 2 == 1:
            _colocar(marcacao, passo, ruido(0.03) * decaimento(0.03, 55.0) * 0.09)
        # Bumbo no 1 e no 3 de cada compasso.
        if passo % 8 in (0, 4):
            _colocar(marcacao, passo, passa_baixa(ruido(0.1), 500)
                     * decaimento(0.1, 20.0) * 0.55)

    return _cortar_no_loop(somar(baixo, arpejo, marcacao))


def musica_perseguicao() -> np.ndarray:
    """Mesma harmonia e mesmo andamento, tocada por cima da base.

    Só entra bateria densa, um baixo em semicolcheias e uma nota aguda insistente.
    Como está no mesmo compasso da base, o jogo pode subir e descer o volume desta
    camada a qualquer momento sem cortar nada nem sair de tempo.
    """
    baixo = _faixa_vazia()
    tensao = _faixa_vazia()
    bateria = _faixa_vazia()

    for passo in range(PASSOS):
        raiz, tríade = _acorde_do_passo(passo)

        # Baixo em todas as colcheias, com quinta descendo: sensação de perseguição.
        f = NOTA[raiz] * (1.5 if passo % 4 == 3 else 1.0)
        _colocar(baixo, passo, quadrada(f, DUR_PASSO * 0.95, 0.25)
                 * decaimento(DUR_PASSO * 0.95, 5.0) * 0.26)

        # Caixa nos tempos 2 e 4.
        if passo % 8 in (2, 6):
            _colocar(bateria, passo, somar(
                ruido(0.11) * decaimento(0.11, 24.0) * 0.42,
                passa_baixa(ruido(0.11), 1400) * decaimento(0.11, 18.0) * 0.3,
            ))
        _colocar(bateria, passo, ruido(0.025) * decaimento(0.025, 70.0) * 0.07)

        # Nota aguda repetida no fim de cada compasso — o "alarme" da camada.
        if passo % 8 == 7:
            _colocar(tensao, passo, quadrada(NOTA[tríade[2]] * 4.0, DUR_PASSO * 0.6, 0.12)
                     * decaimento(DUR_PASSO * 0.6, 9.0) * 0.13)

    return _cortar_no_loop(somar(baixo, tensao, bateria))


## Cada conjunto e um par (base, tensa) que toca SEMPRE junto; so o volume da
## segunda muda com o perigo. O jogo escolhe o conjunto por fase.
CONJUNTOS = {
    "expediente": (musica_expediente, musica_perseguicao),
}


def main() -> None:
    print("efeitos:")
    for nome, fabrica in EFEITOS.items():
        gravar(os.path.join(PASTA_SFX, nome + ".wav"), normalizar(fabrica(), 0.8))

    print("musica (as duas camadas de cada conjunto tem que sair com a MESMA duracao):")
    for nome, (base, tensa) in CONJUNTOS.items():
        sinais = {
            nome: normalizar(base(), 0.62),
            nome + "_tenso": normalizar(tensa(), 0.62),
        }
        duracoes = {len(s) for s in sinais.values()}
        assert len(duracoes) == 1, "conjunto %s dessincronizado: %s" % (nome, duracoes)
        for arquivo, sinal in sinais.items():
            gravar(os.path.join(PASTA_MUSICA, arquivo + ".wav"), sinal)
        print("ok: conjunto '%s' sincronizado (%d amostras)" % (nome, duracoes.pop()))


if __name__ == "__main__":
    main()
