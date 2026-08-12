extends Node

## Banco de provas do HTTPRequest dentro do export web: a consulta que funciona no
## desktop pode cair em "ranking local" no navegador, e a prova "servidor local" separa
## problema de rede de problema de leitura. As provas rodam em paralelo, cada uma no seu
## nó, para que uma travada não esconda as outras.
##
## ATENÇÃO: o Chrome congela o laço de quadros de aba em segundo plano — numa aba oculta,
## 0,2s de jogo depois de um minuto de relógio, e toda requisição parece expirar. Por
## isso o placar também vai para o TÍTULO da janela, legível de fora com:
##   Get-Process chrome | Where-Object { $_.MainWindowTitle -ne "" } | %{ $_.MainWindowTitle }
##
## Uso (main_scene temporariamente apontada para cá):
##   godot --headless --path . --export-release "Web" build/web/index.html
##   python tools/servir_web.py 8060
##   chrome --new-window http://localhost:8060/index.html   # visível, nunca em segundo plano

const ESPERA := 8.0
const PULSO := 2.0

var _provas: Array = []
var _relogio := 0.0
var _proximo_pulso := PULSO
var _placar: PackedStringArray = []


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://supabase.cfg") != OK:
		_anotar("sem supabase.cfg")
		return
	var url: String = str(cfg.get_value("supabase", "url", "")).rstrip("/")
	var chave: String = str(cfg.get_value("supabase", "anon_key", ""))
	var alvo := "%s/rest/v1/ranking?dia=eq.1&limit=10" % url

	_disparar("1 servidor local", "http://localhost:8060/index.html", PackedStringArray(), false)
	_disparar("2 so apikey", alvo, PackedStringArray(["apikey: " + chave]), false)
	_disparar("3 tres cabecalhos", alvo, PackedStringArray([
		"apikey: " + chave, "Authorization: Bearer " + chave,
		"Content-Type: application/json"]), false)
	_disparar("4 tres cabecalhos, gzip ligado", alvo, PackedStringArray([
		"apikey: " + chave, "Authorization: Bearer " + chave,
		"Content-Type: application/json"]), true)


func _disparar(nome: String, url: String, cabecalhos: PackedStringArray, gzip: bool) -> void:
	var no := HTTPRequest.new()
	no.timeout = ESPERA
	no.accept_gzip = gzip
	add_child(no)
	_provas.append([nome, no])
	no.request_completed.connect(func(
		resultado: int, codigo: int, recebidos: PackedStringArray, corpo: PackedByteArray
	) -> void:
		_anotar("%s -> resultado=%d http=%d bytes=%d em %.1fs" % [
			nome, resultado, codigo, corpo.size(), _relogio])
		for c in recebidos:
			if c.to_lower().begins_with("content-encoding"):
				_anotar("   " + nome + ": " + c)
	)
	_anotar("%s request() = %d" % [nome, no.request(url, cabecalhos, HTTPClient.METHOD_GET)])


## Pulso de vida. Sem ele não dá para separar "a requisição não voltou" de "o motor parou":
## nas duas situações a saída é a mesma — silêncio.
func _process(delta: float) -> void:
	_relogio += delta
	if _relogio < _proximo_pulso:
		return
	_proximo_pulso += PULSO
	_anotar("pulso %.0fs" % _relogio)


## Cada linha vai para o console E para window.__prova. O console do navegador se perde a
## cada recarga da página, e ler o resultado de uma prova que já terminou é metade do
## trabalho — window.__prova continua lá para ser lido a qualquer momento.
func _anotar(linha: String) -> void:
	print("[web] ", linha)
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.__prova = (window.__prova||[]).concat([%s])" % JSON.stringify(linha), true
	)
	# O placar também vai para o TÍTULO da aba, e não é enfeite: uma aba em segundo plano
	# tem o laço de quadros congelado pelo Chrome, então a única medição que vale é a de uma
	# janela visível — e numa janela visível não há como ler window.__prova de fora. O
	# título, sim: ele aparece na barra da janela, que qualquer processo consegue ler.
	if not linha.contains("resultado="):
		return
	_placar.append(linha.replace("resultado=", "r=").replace("http=", "h=").replace("bytes=", "b="))
	DisplayServer.window_set_title("PROVA " + " | ".join(_placar))
