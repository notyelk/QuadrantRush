extends CanvasLayer

## Menu de pausa — Etapa 6 da Metodologia ("tela de pausa").
##
## Roda com process_mode ALWAYS porque a árvore fica pausada enquanto ele está
## visível; sem isso os próprios botões não responderiam. Mesmo padrão da tela de
## resultado, que já funciona assim.
##
## Este nó não decide QUANDO aparecer: quem abre e fecha é fase_01.gd, que é o único
## que sabe se o expediente ainda está em curso. Pausar depois do fim do expediente
## empilharia dois painéis na tela.

signal continuar_pedido

const CENA_TITULO := "res://scenes/ui/tela_titulo.tscn"

@onready var botao_continuar: Button = $Painel/Conteudo/Botoes/Continuar
@onready var botao_reiniciar: Button = $Painel/Conteudo/Botoes/Reiniciar
@onready var botao_titulo: Button = $Painel/Conteudo/Botoes/Titulo
@onready var resumo: Label = $Painel/Conteudo/Resumo

## A mesma tecla que abriu o menu ainda está registrada como "recém-apertada" no
## frame em que este nó nasce. Sem ignorar o primeiro frame, o menu se fecharia no
## instante em que abre.
var _primeiro_frame := true


func _ready() -> void:
	botao_continuar.pressed.connect(_ao_continuar)
	botao_reiniciar.pressed.connect(_ao_reiniciar)
	botao_titulo.pressed.connect(_ao_titulo)

	resumo.text = "%s · %d pts · %s no relógio" % [
		Perfil.nickname if not Perfil.nickname.is_empty() else "Sem crachá",
		GameManager.pontuacao_total,
		_formatar(GameManager.tempo_restante),
	]
	botao_continuar.grab_focus()


## Sondagem em vez de _unhandled_input pelo mesmo motivo da fase: Input.action_press()
## não sintetiza InputEvent, e o teste automatizado precisa conseguir fechar o menu.
func _process(_delta: float) -> void:
	if _primeiro_frame:
		_primeiro_frame = false
		return
	if Input.is_action_just_pressed("pausar"):
		_ao_continuar()


func _ao_continuar() -> void:
	Audio.tocar("ui")
	continuar_pedido.emit()


func _ao_reiniciar() -> void:
	Audio.tocar("ui")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _ao_titulo() -> void:
	Audio.tocar("ui")
	get_tree().paused = false
	Audio.parar_musica(0.2)
	get_tree().change_scene_to_file(CENA_TITULO)


func _formatar(segundos: float) -> String:
	return "%02d:%02d" % [int(segundos) / 60, int(segundos) % 60]
