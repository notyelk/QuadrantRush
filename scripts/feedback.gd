extends RefCounted
class_name Feedback

## Pequenos avisos flutuantes ("+100", "-8s") que sobem e somem no ponto onde a ação
## aconteceu. Fica num arquivo próprio porque tarefa.gd, bifurcacao_q3.gd e
## ladrao_de_tempo.gd precisam exatamente do mesmo efeito — não vale duplicar em três.
##
## É estático de propósito: quem chama passa o nó-pai (a fase), então o aviso sobrevive
## ao queue_free() da tarefa que o originou.

const DURACAO := 0.9
const SUBIDA := 22.0


static func pontos(pai: Node, posicao: Vector2, texto: String, cor: Color) -> void:
	if pai == null or not pai.is_inside_tree():
		return

	var rotulo := Label.new()
	rotulo.text = texto
	rotulo.z_index = 20
	rotulo.add_theme_font_size_override("font_size", 8)
	rotulo.add_theme_color_override("font_color", cor)
	rotulo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	rotulo.add_theme_constant_override("outline_size", 3)
	# Centraliza horizontalmente sobre o ponto da ação sem depender do tamanho do texto.
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.size = Vector2(60, 12)
	rotulo.pivot_offset = Vector2(30, 6)
	rotulo.global_position = posicao - Vector2(30, 14)

	pai.add_child(rotulo)

	# Entra estourando e assenta: um número que só aparece se perde no meio de tudo
	# que está acontecendo na tela; um que "salta" é lido mesmo de canto de olho.
	rotulo.scale = Vector2(0.4, 0.4)
	var entrada := rotulo.create_tween()
	entrada.tween_property(rotulo, "scale", Vector2(1.25, 1.25), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrada.tween_property(rotulo, "scale", Vector2.ONE, 0.1)

	var tween := rotulo.create_tween()
	tween.set_parallel(true)
	tween.tween_property(rotulo, "global_position:y", rotulo.global_position.y - SUBIDA, DURACAO) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(rotulo, "modulate:a", 0.0, DURACAO).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(rotulo.queue_free)


## Estouro de partículas no ponto da ação. Mesmo motivo de pontos() para ser estático
## e receber o pai: a tarefa que gerou o efeito costuma ser liberada no mesmo frame.
##
## CPUParticles2D (e não GPUParticles2D) porque o projeto roda em GL Compatibility,
## exigência do export WebGL da Etapa 9 — partículas de GPU não são confiáveis nesse
## renderizador. Sem textura, cada partícula é um quadradinho de 1–2px, que é
## exatamente o tamanho certo para pixel art num viewport de 400x208.
static func estouro(
	pai: Node, posicao: Vector2, cor: Color, quantidade: int = 14, forca: float = 70.0
) -> void:
	if pai == null or not pai.is_inside_tree():
		return

	var p := CPUParticles2D.new()
	p.global_position = posicao
	p.z_index = 19
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = quantidade
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = forca * 0.45
	p.initial_velocity_max = forca
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = cor
	pai.add_child(p)

	# Autolimpeza: sem isso cada coleta deixaria um nó morto na cena até o fim da
	# fase. O tempo de vida + folga garante que ninguém suma no meio da animação.
	var morte := p.create_tween()
	morte.tween_interval(p.lifetime + 0.35)
	morte.tween_callback(p.queue_free)


## Anel que expande e some — leitura de "algo aconteceu AQUI" mais forte que o
## estouro sozinho, usado no acerto do urso e na liberação da saída.
static func onda(pai: Node, posicao: Vector2, cor: Color, raio: float = 46.0) -> void:
	if pai == null or not pai.is_inside_tree():
		return

	var anel := Line2D.new()
	anel.width = 2.0
	anel.default_color = cor
	anel.closed = true
	anel.z_index = 19
	anel.global_position = posicao
	var lados := 18
	for i in lados:
		var a := TAU * i / lados
		anel.add_point(Vector2(cos(a), sin(a)) * 8.0)
	pai.add_child(anel)

	var t := anel.create_tween()
	t.set_parallel(true)
	t.tween_property(anel, "scale", Vector2.ONE * (raio / 8.0), 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(anel, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(anel.queue_free)
