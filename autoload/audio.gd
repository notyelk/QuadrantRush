extends Node

## Toca todo o som do jogo. Os arquivos vêm de tools/audio_gen.py; se um faltar, o jogo
## avisa uma vez e segue mudo naquele efeito.
##
## Polifonia por pool, porque um AudioStreamPlayer toca um som por vez. Cada pedido usa
## o primeiro tocador livre, com ±6% de variação de altura.
##
## A trilha são duas faixas de mesma duração, `<nome>.wav` e `<nome>_tenso.wav`, tocadas
## sempre juntas e sincronizadas; só o volume da segunda muda, conforme intensidade().
## Trocar de conjunto (FaseBase.conjunto_musical) só entre fases, com a música parada.

const PASTA_SFX := "res://audio/sfx/"
const PASTA_MUSICA := "res://audio/musica/"

const TOCADORES := 12

## Volume da camada de perseguição quando o perigo é zero. -40dB é praticamente
## inaudível, mas mantém a faixa rodando e em sincronia.
const PERSEGUICAO_MIN_DB := -40.0
const PERSEGUICAO_MAX_DB := -7.0
const MUSICA_DB := -11.0

var _sfx: Array[AudioStreamPlayer] = []
var _proximo := 0
var _cache: Dictionary = {}
var _faltando: Dictionary = {}

var _musica_base: AudioStreamPlayer
var _musica_tensa: AudioStreamPlayer
var _intensidade := 0.0
var _intensidade_alvo := 0.0
## Qual par de faixas está carregado. Trocar de conjunto troca os dois fluxos de uma
## vez — nunca só um, senão as camadas deixam de ser a mesma música.
var _conjunto := ""


func _ready() -> void:
	# Continua tocando com a árvore pausada: a tela de resultado pausa o jogo e
	# ainda precisa do som de vitória/derrota e dos cliques.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_barramentos()
	_criar_tocadores()
	_criar_musica()


func _process(delta: float) -> void:
	if _musica_tensa == null:
		return
	# Suaviza a subida e a descida: o volume acompanhar o perigo quadro a quadro
	# faria a bateria "piscar" toda vez que o jogador pulasse para trás.
	_intensidade = move_toward(_intensidade, _intensidade_alvo, delta * 0.8)
	_musica_tensa.volume_db = lerpf(PERSEGUICAO_MIN_DB, PERSEGUICAO_MAX_DB, _intensidade)


## Toca um efeito pelo nome do arquivo (sem .wav). `desvio` é a variação máxima de
## altura, em fração — 0 desliga a variação (usado no que precisa soar idêntico
## sempre, como a fanfarra de vitória).
func tocar(nome: String, volume_db: float = 0.0, desvio: float = 0.06) -> void:
	var fluxo := _carregar(PASTA_SFX + nome + ".wav")
	if fluxo == null:
		return

	var tocador := _tocador_livre()
	tocador.stream = fluxo
	tocador.volume_db = volume_db
	tocador.pitch_scale = 1.0 + randf_range(-desvio, desvio)
	tocador.play()


## `conjunto` escolhe o par de faixas. Cada conjunto tem um arquivo base e um `_tenso`
## de mesma duração; hoje existe só "expediente", que é o escritório dos dois dias.
func iniciar_musica(conjunto: String = "expediente") -> void:
	if conjunto != _conjunto:
		_trocar_conjunto(conjunto)
	if _musica_base == null:
		return
	# Volume restaurado à mão: parar_musica() esmaece até -60dB, e sem isto a fase
	# seguinte começaria muda.
	_musica_base.volume_db = MUSICA_DB
	_intensidade = 0.0
	_intensidade_alvo = 0.0
	_musica_tensa.volume_db = PERSEGUICAO_MIN_DB
	# Tocar as duas no mesmo frame é o que garante a sincronia das camadas.
	_musica_base.play()
	_musica_tensa.play()


func parar_musica(esmaecer: float = 0.6) -> void:
	if _musica_base == null:
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(_musica_base, "volume_db", -60.0, esmaecer)
	t.tween_property(_musica_tensa, "volume_db", -60.0, esmaecer)
	await t.finished
	_musica_base.stop()
	_musica_tensa.stop()


## 0 = expediente tranquilo, 1 = urso em cima. Chamado pela fase a partir do sinal
## `perigo_mudou` do urso.
func intensidade(valor: float) -> void:
	_intensidade_alvo = clampf(valor, 0.0, 1.0)


## Abafa a trilha enquanto o jogador está concentrado. Não é enfeite: o modo foco muda o
## estado do mundo (as distrações param de acertar) e uma mudança de estado que não se
## ouve nem se vê é uma mudança que o jogador não sabe que fez.
func abafar(ativo: bool) -> void:
	var barramento := AudioServer.get_bus_index("Musica")
	if barramento == -1:
		return
	AudioServer.set_bus_volume_db(barramento, -9.0 if ativo else 0.0)


func _criar_barramentos() -> void:
	# Criados em código em vez de um default_bus_layout.tres: são só dois, e assim
	# não há um arquivo binário de recurso no repositório para dar merge conflict.
	for nome in ["Musica", "SFX"]:
		if AudioServer.get_bus_index(nome) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nome)
		AudioServer.set_bus_send(i, "Master")


func _criar_tocadores() -> void:
	for i in TOCADORES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx.append(p)


func _criar_musica() -> void:
	_trocar_conjunto("expediente")


func _trocar_conjunto(conjunto: String) -> void:
	var base := _carregar(PASTA_MUSICA + conjunto + ".wav")
	var tensa := _carregar(PASTA_MUSICA + conjunto + "_tenso.wav")
	if base == null or tensa == null:
		return

	# Os nós são criados uma vez e só trocam de fluxo. Recriar AudioStreamPlayer a
	# cada fase vazaria um par por partida jogada.
	if _musica_base == null:
		_musica_base = _criar_camada(MUSICA_DB)
		_musica_tensa = _criar_camada(PERSEGUICAO_MIN_DB)

	_musica_base.stop()
	_musica_tensa.stop()
	_musica_base.stream = base
	_musica_tensa.stream = tensa
	_conjunto = conjunto


func _criar_camada(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Musica"
	p.volume_db = db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## Escolhe um tocador livre; se todos estiverem ocupados, reaproveita em rodízio o
## mais antigo. Cortar o som mais velho é sempre melhor do que engolir o novo — o
## jogador está prestando atenção no que acabou de acontecer.
func _tocador_livre() -> AudioStreamPlayer:
	for p in _sfx:
		if not p.playing:
			return p
	var escolhido := _sfx[_proximo]
	_proximo = (_proximo + 1) % _sfx.size()
	return escolhido


func _carregar(caminho: String) -> AudioStream:
	if _cache.has(caminho):
		return _cache[caminho]
	if not ResourceLoader.exists(caminho):
		if not _faltando.has(caminho):
			_faltando[caminho] = true
			push_warning("Audio: arquivo ausente (%s). Rode 'python tools/audio_gen.py'." % caminho)
		return null

	var fluxo := load(caminho) as AudioStream
	if fluxo is AudioStreamWAV:
		# O importador de WAV não marca loop, e a música precisa emendar sozinha.
		# Ajustar aqui evita ter que versionar um .import editado à mão, que o
		# editor sobrescreveria na próxima reimportação.
		var wav := fluxo as AudioStreamWAV
		if caminho.begins_with(PASTA_MUSICA):
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = 0

	_cache[caminho] = fluxo
	return fluxo
