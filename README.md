# Quadrant Rush — um *serious game* de priorização de tarefas

Jogo 2D de corredor em que você atravessa um dia de trabalho decidindo, com o corpo, o que
merece a sua atenção. Cada tarefa que aparece é um papel com um enunciado e nada mais: o
jogo **não diz** de que quadrante ela é. Quem classifica é você, e a resposta é um
movimento — encostar é fazer agora, passar reto é deixar para lá, subir na bandeja do
colega é delegar. Só depois de agir você descobre em que quadrante da **Matriz de
Eisenhower** aquilo caía.

Produto prático do Trabalho de Conclusão de Curso em Engenharia de Software (UNINTER).

**Jogue no navegador:** https://notyelk.itch.io/quadrant-rush

---

## Como jogar

| Tecla | Ação |
|---|---|
| `A` `D` ou `←` `→` | correr |
| `W` ou `↑` | pular (segurar pula mais alto) |
| `Shift` ou `L` | modo foco — anda devagar, lê de longe, não leva encontrão |
| `S` ou `↓` | largar o papel que está na mão (Dia 3) |
| `ESC` ou `P` | pausar |

Nos dois primeiros dias você tem um expediente cronometrado para chegar ao elevador, e ele
só abre depois de um número mínimo de tarefas **urgentes e importantes** resolvidas —
correr direto para a saída não funciona.

### Os três dias

1. **O primeiro dia** — as tarefas estão paradas no corredor, e você escolhe a ordem. Um
   urso chamado "O Prazo" persegue você o expediente inteiro. Aqui entram a pasta (o que
   você faz e não entrega vira peso) e o modo foco (ler devagar, andar devagar).
2. **O dia das interrupções** — as tarefas chegam sozinhas, na ordem de uma agenda, e
   notificações apagam o enunciado enquanto você tenta ler. E o que você deixa passar
   **volta**: uma tarefa *importante e não urgente* adiada amadurece e reaparece como
   *urgente e importante*, obrigatória para o elevador abrir. O dia de quem procrastina
   fica maior, não menor.
3. **A reunião de encerramento** — a sala inteira **é** a matriz: cada canto do escritório
   representa um quadrante. O chefe despeja demandas do alto e você carrega **um papel por
   vez** até o canto certo. O verbo deixa de ser *coletar* e passa a ser *rotear*: o canto
   para onde você leva o papel é a sua resposta sobre em que quadrante ele estava. Aqui o
   relógio muda de lado — sobreviver ao expediente é vencer, e quem derruba você é a pilha
   de pendências mal classificadas. E o mapa é **sorteado a cada partida**, para que
   decorar não substitua classificar.

### Como a pontuação funciona

| Quadrante | O que fazer | Efeito |
|---|---|---|
| Urgente e importante | resolver agora | +100 |
| Importante, não urgente | resolver com folga | +80 |
| Urgente, não importante | delegar / resolver sozinho | +60 / +40 e −5s |
| Nem urgente nem importante | desviar | colidir: −20 e −8s |

No fim de cada dia o jogo mostra o desempenho **por quadrante**, não só o placar: quantas
urgentes você tratou, quantas importantes deixou para trás, quantas você delegou em vez de
fazer sozinho. É esse relatório, e não o número final, o ponto do jogo.

## Rodar a partir do código

Requer [Godot Engine 4.6](https://godotengine.org/) — sem plugins, sem dependências.

```bash
godot --path .                     # abre no editor
godot --path . res://scenes/ui/tela_titulo.tscn   # roda direto
```

### Testes

GDScript puro, sem framework externo. Cada suíte dirige a fase de verdade e sai com código
1 se algo falhar.

```bash
godot --headless --path . res://tests/teste_fase_01.tscn
godot --headless --path . res://tests/teste_fase_02.tscn
godot --headless --path . res://tests/teste_fase_03.tscn
godot --headless --path . res://tests/teste_ranking.tscn
```

Eles não verificam só regras: um dos cenários atravessa o corredor **a pé**, com a física
real e as mesmas teclas de um humano, e outro confere cada degrau contra a trajetória
integrada do pulo. Foi assim que a geometria das fases parou de depender de conferência
visual. Como o Dia 3 é sorteado, o teste dele varre 200 sementes e exige as mesmas
invariantes em todas — e também quebra a geometria de propósito, para provar que o
validador recusa um mapa impossível em vez de aceitar qualquer coisa.

### Ranking em nuvem (opcional)

O jogo funciona sem configurar nada — as partidas ficam num ranking local e a tela diz
isso. Para ligar o ranking global:

1. Crie um projeto gratuito em [supabase.com](https://supabase.com).
2. Rode [`supabase/schema.sql`](supabase/schema.sql) no SQL Editor do projeto.
3. Copie `supabase.cfg.exemplo` para `supabase.cfg` e preencha a URL e a chave pública do
   projeto (`anon public` nos projetos antigos, `publishable` nos novos). A chave secreta
   (`service_role`) não entra aqui e não entra em lugar nenhum do jogo: quem protege a
   tabela é a *Row Level Security* declarada no `schema.sql`.

Nada de plugin: a comunicação é feita com o nó `HTTPRequest` da própria engine, contra a
API REST do Supabase.

## Estrutura

```
autoload/     estado global: placar e cronômetro, perfil, áudio, juice, cliente Supabase
scenes/       player, fases, tarefas, telas de interface, tilesets
scripts/      comportamento das cenas (fase_base.gd é o que os três dias têm em comum)
entities/     urso, colega, plataformas, notificações, caixa de saída
tests/        suítes automatizadas
tools/        geradores de fase, sintetizador de áudio, ferramentas de captura
supabase/     esquema SQL do banco em nuvem
```

## Licença

Código sob [MIT](LICENSE). Arte e áudio têm procedência própria, listada em
[CREDITOS.md](CREDITOS.md) — todo o áudio é sintetizado pelo próprio projeto.
