extends Node

## Mede o pico de áudio na saída do Master, para conferir se o jogo está mudo.
##
##     godot --path . res://tools/checar_audio.tscn
##
## Rodar como cena (em --script não há autoload) e com driver real (--headless usa o
## driver Dummy e mede zero). Para medir o export web, apontar `run/main_scene` para cá,
## exportar para uma pasta descartável e ler o console do navegador.

const SILENCIO := 0.001


func _ready() -> void:
	print("driver de audio: ", AudioServer.get_driver_name())
	print("mix rate: ", AudioServer.get_mix_rate())
	print("barramentos: ", _listar_barramentos())

	var master := AudioServer.get_bus_index("Master")
	var captura := AudioEffectCapture.new()
	captura.buffer_length = 2.0
	AudioServer.add_bus_effect(master, captura)

	_diagnosticar("res://audio/sfx/coleta.wav")
	_diagnosticar("res://audio/musica/expediente.wav")

	# Tocadores soltos, fora do autoload, para isolar o Master dos barramentos criados
	# em tempo de execução.
	var solto := AudioStreamPlayer.new()
	solto.stream = load("res://audio/sfx/coleta.wav")
	solto.bus = "Master"
	add_child(solto)

	var no_sfx := AudioStreamPlayer.new()
	no_sfx.stream = load("res://audio/sfx/coleta.wav")
	no_sfx.bus = "SFX"
	add_child(no_sfx)

	var mudos := 0
	mudos += 1 if await _medir("direto no Master", captura,
		func() -> void: solto.play()) else 0
	mudos += 1 if await _medir("direto no SFX", captura,
		func() -> void: no_sfx.play()) else 0
	mudos += 1 if await _medir("efeito coleta", captura,
		func() -> void: Audio.tocar("coleta")) else 0
	mudos += 1 if await _medir("efeito pulo", captura,
		func() -> void: Audio.tocar("pulo")) else 0
	mudos += 1 if await _medir("musica expediente", captura,
		func() -> void: Audio.iniciar_musica("expediente"), 2.0) else 0

	print("resultado: ", "MUDO em %d de 5" % mudos if mudos > 0 else "som saindo nos 5")
	get_tree().quit(1 if mudos > 0 else 0)


func _medir(nome: String, captura: AudioEffectCapture, acao: Callable,
		segundos: float = 1.0) -> bool:
	captura.clear_buffer()
	acao.call()

	var fim := Time.get_ticks_msec() + int(segundos * 1000.0)
	var pico := 0.0
	var lidos := 0
	while Time.get_ticks_msec() < fim:
		await get_tree().process_frame
		var quantos := captura.get_frames_available()
		if quantos <= 0:
			continue
		for quadro in captura.get_buffer(quantos):
			pico = maxf(pico, maxf(absf(quadro.x), absf(quadro.y)))
			lidos += 1

	var mudo := pico < SILENCIO
	print("%-20s pico=%.4f  amostras=%d  %s" % [nome, pico, lidos, "MUDO" if mudo else "ok"])
	return mudo


## Formato e tamanho do arquivo, para separar "não carregou" de "carregou e não toca".
func _diagnosticar(caminho: String) -> void:
	if not ResourceLoader.exists(caminho):
		print("%-34s AUSENTE do pacote" % caminho)
		return
	var fluxo := load(caminho) as AudioStream
	if fluxo == null:
		print("%-34s carregou como nulo" % caminho)
		return
	var extra := ""
	if fluxo is AudioStreamWAV:
		var w := fluxo as AudioStreamWAV
		extra = "  formato=%d  estereo=%s  taxa=%d  bytes=%d" % [
			w.format, w.stereo, w.mix_rate, w.data.size()]
	print("%-34s %s  dur=%.2fs%s" % [caminho, fluxo.get_class(), fluxo.get_length(), extra])


func _listar_barramentos() -> String:
	var partes: PackedStringArray = []
	for i in AudioServer.bus_count:
		partes.append("%s(%.1fdB%s)" % [
			AudioServer.get_bus_name(i),
			AudioServer.get_bus_volume_db(i),
			", mudo" if AudioServer.is_bus_mute(i) else "",
		])
	return ", ".join(partes)
