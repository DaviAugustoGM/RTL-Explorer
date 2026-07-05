# Explicacao do RTL Explorer

Este documento explica como o projeto foi montado. A ideia e ajudar voce a entender Tcl/Tk e a organizacao do codigo sem precisar conhecer tudo de uma vez.

## O que e este projeto

O RTL Explorer e uma interface grafica feita em Tcl/Tk para visualizar modulos SystemVerilog como blocos em um diagrama.

Hoje ele ja consegue:

- abrir arquivos `.sv` ou uma pasta com arquivos `.sv`;
- detectar modulos e portas simples;
- mostrar uma arvore do projeto;
- mostrar uma biblioteca de blocos;
- arrastar blocos para um canvas;
- criar conexoes entre portas;
- mover e redimensionar blocos;
- salvar o projeto em `.rtlex`;
- abrir um projeto `.rtlex` salvo.

## Como iniciar

O arquivo principal e:

```text
src/main.tcl
```

Para rodar:

```powershell
wish src/main.tcl
```

Use `wish`, nao `tclsh`, porque `wish` ja inicia com suporte a janelas Tk.

## Ideia basica de Tcl/Tk

Tcl e a linguagem. Tk e a biblioteca grafica.

Em Tk, quase tudo e um widget. Exemplos:

- `ttk::frame`: painel/area de layout.
- `label`: texto clicavel ou informativo.
- `ttk::treeview`: arvore lateral.
- `ttk::notebook`: abas.
- `canvas`: area para desenhar blocos, linhas e formas.
- `text`: caixa de texto usada no console e propriedades.

Um exemplo simples:

```tcl
label .hello -text "Oi"
pack .hello
```

Isso cria um texto na janela.

## Estrutura dos arquivos

O projeto foi dividido em arquivos menores para nao deixar tudo em `main.tcl`.

```text
src/
  main.tcl                Entrada do programa
  theme.tcl               Cores e estilos dark
  layout.tcl              Monta a janela e menus
  project_tree.tcl        Explorer e biblioteca de blocos
  canvas_blocks.tcl       Desenha/move/redimensiona blocos
  canvas_connections.tcl  Cria, seleciona e remove conexoes
  properties_panel.tcl    Painel de propriedades
  console.tcl             Console inferior
  sv_parser.tcl           Parser simples de SystemVerilog
  fsm_viewer.tcl          Aba inicial de FSM
  simulation_model.tcl    Converte o diagrama em um projeto sintetizavel
  simulation_components.tcl Blocos de entrada, probe e clock
  diagram_simulation.tcl  Valores e cores sobre o diagrama
  demo_scenarios.tcl      Cenarios sincronizados de demonstracao
  simulator_view.tcl      Interface e controles da simulacao
  pdf_export.tcl          Exportacao vetorial de diagramas para PDF
  netlist_sim.py          Executa o netlist JSON gerado pelo Yosys
  documentation.tcl       Aba inicial de documentacao
```

## main.tcl

Este e o ponto de entrada.

Ele faz tres coisas principais:

1. Carrega todos os outros arquivos com `source`.
2. Define variaveis globais do app.
3. Chama `::svvs::boot`.

O trecho:

```tcl
source [file join $::APP_DIR theme.tcl]
source [file join $::APP_DIR layout.tcl]
```

significa: "leia esse outro arquivo Tcl e carregue os comandos dele".

O projeto usa namespaces, por exemplo:

```tcl
namespace eval ::svvs {
    variable appName "RTL Explorer"
}
```

Isso ajuda a organizar nomes e evitar conflitos.

## theme.tcl

Aqui ficam as cores e estilos.

Exemplo:

```tcl
array set colors {
    bg #1e1e1e
    panel #252526
    accent #007acc
}
```

Isso cria uma tabela de cores.

Depois usamos:

```tcl
::svvs::theme::color bg
```

para pegar a cor `#1e1e1e`.

Tambem configuramos widgets `ttk`, como botoes, abas e arvore.

## layout.tcl

Este arquivo monta a janela.

Ele cria:

- menu superior;
- barra lateral de icones;
- painel esquerdo;
- canvas central;
- painel direito de propriedades;
- console inferior.

O layout usa bastante:

```tcl
ttk::panedwindow
```

Esse widget divide a tela em areas redimensionaveis.

O menu `File` tambem fica aqui. Ele tem:

- `Open Project`
- `Open Files`
- `Open Folder`
- `Save Project`
- `Export PDF > Block Diagram`
- `Export PDF > State Machine`
- `Close Project`

Quando voce clica em `Save Project`, ele chama:

```tcl
::svvs::layout::saveProject
```

Essa funcao abre a janela para salvar um arquivo `.rtlex`.

## Exportacao para PDF

Use **File > Export PDF** para escolher o diagrama de blocos ou a maquina de
estados atualmente aberta. Antes de salvar, escolha **White document**, opcao
padrao para relatorios, ou **Original dark colors**. O tema branco converte
fundo, blocos, textos, fios e portas para uma paleta clara com contraste de
impressao; ele nao troca somente a cor do fundo. O exportador inclui todo o
canvas, mesmo as partes fora da area visivel, escolhe A4 retrato ou paisagem
automaticamente e ajusta o conteudo a pagina. Alcas e linhas invisiveis usadas
para cliques nao aparecem.

O atalho `Ctrl+P` exporta a visualizacao atual: a FSM quando essa aba esta
selecionada e o diagrama de blocos nas demais abas. A geracao e feita pelo
proprio RTL Explorer e nao depende de Ghostscript ou impressora instalada.

## project_tree.tcl

Este arquivo controla a arvore lateral.

Ele usa:

```tcl
ttk::treeview
```

A arvore pode mostrar duas coisas:

1. O projeto aberto.
2. A biblioteca de blocos, no modo Blocos.

Quando abre uma pasta com `.sv`, o projeto chama:

```tcl
::svvs::project_tree::loadProjectFiles
```

Essa funcao salva os arquivos abertos e chama o parser para detectar modulos.

No modo Blocos, a arvore mostra:

```text
Component Library
  User modules
  Built-in blocks
    Sources
    Logic
    Storage
```

Os blocos podem ser arrastados para o canvas.

## sv_parser.tcl

Este ainda e um parser simples.

Ele procura textos como:

```systemverilog
module producer (
    input logic clk,
    output logic valid
);
endmodule
```

E transforma isso em uma estrutura Tcl parecida com:

```tcl
dict create name producer instance u_producer ports {...}
```

Em Tcl, `dict` e parecido com um objeto simples ou mapa chave/valor.

Exemplo:

```tcl
set module [dict create name producer instance u_producer]
dict get $module name
```

retorna:

```text
producer
```

## canvas_blocks.tcl

Este e um dos arquivos mais importantes.

Ele desenha blocos no `canvas`.

Um bloco e composto por varios itens:

- retangulo principal;
- cabecalho;
- titulo;
- bolinhas das portas;
- textos das portas;
- alca de redimensionamento.

Cada item recebe tags. Exemplo:

```tcl
-tags [list $tag block-body]
```

Tags sao muito importantes no canvas. Elas permitem mover ou selecionar varias formas juntas.

Por exemplo, se um bloco tem tag:

```text
block:block1
```

podemos mover tudo com:

```tcl
$canvas move block:block1 10 0
```

Isso move o bloco 10 pixels para a direita.

## Como o bloco e movido

Quando voce clica no canvas, Tk dispara este evento:

```tcl
bind $canvas <ButtonPress-1> {::svvs::canvas_blocks::onPress %x %y}
```

`%x` e `%y` sao as coordenadas do mouse.

Quando arrasta:

```tcl
bind $canvas <B1-Motion> {::svvs::canvas_blocks::onDrag %x %y}
```

O codigo calcula a diferenca entre a posicao antiga e a nova:

```tcl
set dx [expr {$x - $dragLastX}]
set dy [expr {$y - $dragLastY}]
```

E move o bloco:

```tcl
$canvas move $dragTag $dx $dy
```

Depois chama:

```tcl
::svvs::canvas_connections::refreshAll
```

para atualizar as conexoes.

## canvas_connections.tcl

Este arquivo cria as linhas entre portas.

Uma conexao tambem tem tags, por exemplo:

```text
conn:1
```

Para desenhar uma conexao, o codigo descobre o centro da porta de origem e o centro da porta de destino.

Depois desenha uma linha:

```tcl
$canvas create line ...
```

Tambem existe uma segunda linha invisivel mais grossa. Ela serve para facilitar o clique na conexao.

Assim voce nao precisa clicar exatamente em cima de uma linha muito fina.

## Como deletar uma conexao

Quando uma conexao e selecionada, a variavel:

```tcl
selectedTag
```

recebe algo como:

```text
conn:1
```

Quando voce aperta `Delete`, o app chama:

```tcl
::svvs::canvas_blocks::deleteSelected
```

Se a selecao comeca com `conn:`, ele apaga a conexao.

## properties_panel.tcl

Este arquivo controla o painel da direita.

Quando voce seleciona um bloco, ele mostra:

- tipo;
- modulo;
- instancia;
- portas.

Quando seleciona uma porta ou conexao, mostra dados especificos daquele item.

Internamente ele usa widget `text`, que e uma caixa de texto.

## console.tcl

Este arquivo controla o console inferior.

Chamamos:

```tcl
::svvs::console::log "Mensagem"
```

para escrever uma mensagem com horario.

Exemplo:

```text
[12:04:33] Projeto salvo: teste.rtlex
```

## Salvamento .rtlex

O arquivo `.rtlex` e salvo como uma estrutura Tcl `dict`.

Ele guarda:

- formato;
- versao;
- data;
- projeto;
- arquivos abertos;
- modulos;
- blocos;
- posicao dos blocos;
- tamanho dos blocos;
- conexoes;
- configuracoes como zoom e nomes das portas.

O salvamento fica em:

```tcl
::svvs::layout::saveProjectTo
```

A abertura fica em:

```tcl
::svvs::layout::openProjectFrom
```

## Pasta sample

A pasta:

```text
sample/
```

tem dois arquivos simples:

```text
producer.sv
consumer.sv
```

Voce pode abrir com:

```text
File > Open Folder
```

e escolher a pasta `sample`.

## Ordem recomendada para estudar

Se voce quer aprender o codigo, leia nesta ordem:

1. `src/main.tcl`
2. `src/theme.tcl`
3. `src/layout.tcl`
4. `src/console.tcl`
5. `src/project_tree.tcl`
6. `src/sv_parser.tcl`
7. `src/canvas_blocks.tcl`
8. `src/canvas_connections.tcl`

O visualizador de FSM detecta enums e transicoes em blocos `case`. Ao clicar em
um arquivo `.sv` na pasta **files** ou em um modulo na pasta **modules**, a aba
**FSM** abre automaticamente a primeira maquina de estados correspondente. Se o
arquivo ou modulo possuir mais de uma, cada maquina continua disponivel
individualmente na pasta **state machines**. Arquivos do Explorer nao sao
arrastaveis e nunca adicionam blocos ao diagrama.
Quando o modulo selecionado nao possui FSM, o diagrama anterior e removido e a
aba informa explicitamente que nenhuma maquina foi detectada naquele modulo.

O layout usa mais linhas quando existem muitos estados, desenha os estados em
circulos dimensionados pelo maior nome e mantem espacamento fixo mesmo em telas grandes. Transicoes
incondicionais nao mostram o rotulo redundante `default`. Zoom e arraste do campo
de visao continuam disponiveis para diagramas extensos.

## Conceitos importantes para aprender

Estude estes conceitos de Tcl/Tk:

- `proc`: cria funcoes.
- `namespace`: organiza nomes.
- `variable`: acessa variaveis dentro de namespace.
- `dict`: estrutura chave/valor.
- `list`: listas Tcl.
- `bind`: conecta eventos do mouse/teclado a funcoes.
- `canvas`: desenho 2D.
- `tags` do canvas: agrupam itens desenhados.
- `ttk::treeview`: arvore lateral.
- `ttk::panedwindow`: layout dividido.
- `tk_getOpenFile`: janela de abrir arquivo.
- `tk_getSaveFile`: janela de salvar arquivo.

## Uma dica mental

Pense no app como camadas:

```text
Arquivos .sv
    -> Parser simples
        -> Modelo em dict/list
            -> Treeview e Canvas
                -> Save/Open .rtlex
```

O parser transforma texto em dados.
O canvas transforma dados em desenhos.
O `.rtlex` salva esses dados para restaurar depois.
## Simulacao ao vivo

A simulacao foi separada em tres camadas para que a interface nao dependa dos
detalhes internos do Yosys:

1. `simulation_model.tcl` le os blocos e conexoes do diagrama. Ele cria um
   modulo superior chamado `rtl_explorer_top`. Entradas sem uma saida dirigindo
   a rede viram entradas externas; cada saida de modulo vira tambem um sinal
   observavel.
2. O Yosys le os arquivos `.sv` dos modulos presentes no diagrama junto com o modulo superior, executa
   `proc`, `flatten`, `opt` e `memory`, e grava o resultado em
   `.rtl_explorer_build/netlist.json`.
3. `netlist_sim.py` mantem os valores dos bits e executa as celulas do JSON. A
   GUI envia comandos simples para mudar entradas, avaliar a logica ou gerar uma
   borda de clock. O processo devolve os novos valores sem interromper a
   simulacao.

A aba **Simulation** e implementada em `simulator_view.tcl`. **Build** refaz a
sintese, **Run** gera ciclos continuamente, **Pause** preserva o estado, **Stop**
reinicia o estado e **Step** executa uma borda de clock. Entradas de um bit usam
uma caixa de selecao; barramentos aceitam um valor decimal.

Depois do `Build`, `diagram_simulation.tcl` leva a simulacao para o proprio
diagrama. Os valores aparecem ao lado das portas, entradas podem ser clicadas e
as conexoes mudam de cor de acordo com o valor atual. A aba **Simulation** fica
como uma visao auxiliar para editar sinais e acompanhar o historico.

Na biblioteca **Simulation I/O** existem tres componentes especiais:

- `input_signal`: fornece um valor em binario, decimal ou hexadecimal;
- `output_probe`: observa uma rede e mostra seu valor;
- `clock_generator`: gera clock na frequencia definida pelo usuario.

`input_signal` e `output_probe` adotam automaticamente a largura da porta a que
sao conectados. Clique com o botao direito para escolher formato, frequencia e
se o sinal deve aparecer em **Live Waveforms**. Um duplo clique edita diretamente
o valor de uma entrada ou a frequencia de um clock.

Esses dois blocos possuem uma alca no canto inferior direito, igual aos modulos
SystemVerilog. Arraste a alca para alterar livremente largura e altura. O valor
ou texto central se ajusta ao espaco disponivel, as conexoes acompanham o novo
tamanho e as dimensoes sao preservadas no projeto `.rtlex`.

No menu de contexto de `output_probe`, **Value labels...** cria nomes para
valores numericos. O campo **Value** aceita binario com prefixo `0b`, hexadecimal
com `0x` ou decimal sem prefixo. Por exemplo, `0b00 = IDLE`, `0x1 = READ` e
`2 = WRITE`. Durante a simulacao, o texto aparece no bloco, na lista de saidas e
na waveform. Valores sem mapeamento continuam usando o formato numerico
selecionado. O mapa acompanha o bloco quando o projeto `.rtlex` e salvo.

O painel **Live Waveforms** fica permanentemente entre a area de trabalho e o
console. As duas divisorias podem ser arrastadas para ajustar a altura do
diagrama, do grafico e do console sem trocar de aba.
Quando a tela e pequena ou existem muitos sinais, o painel oferece rolagem
vertical, encurta apenas os rotulos longos e preserva a largura util das ondas.

O eixo horizontal usa tempo real, portanto alterar outra entrada nao alonga o
pulso do clock. Sinais de um bit aparecem como degraus. Barramentos aparecem
como faixas com bordas inclinadas nas transicoes e um valor por intervalo,
evitando textos sobrepostos.

## Cenarios de demonstracao

Na aba **Simulation**, a secao **Demo Scenarios** permite criar uma demonstracao
com nome e capturar os valores atuais dos blocos de entrada como passos. Em
**Hold until**, cada passo pode aguardar:

- **Time**: uma duracao em milissegundos;
- **Rising**: a proxima borda de subida do clock escolhido;
- **Falling**: a proxima borda de descida;
- **Cycles**: uma quantidade de bordas de subida.

O valor das entradas e aplicado primeiro e permanece estavel ate o evento
escolhido. Assim, para testar um registrador na subida do clock, escolha
**Rising**, selecione o bloco de clock e use **Add step**. **Play** executa a
sequencia com o mesmo clock exibido na waveform. O botao **Step** tambem conta
como uma borda de subida. Os cenarios sao armazenados dentro do `.rtlex`.

O menu **Click action** de `input_signal` tambem oferece slider e pulso
momentaneo. O slider e adequado a barramentos; o pulso coloca a entrada em um e
retorna para zero depois do intervalo configurado.

Durante a simulacao, sinais internos de estado detectados pelo parser sao
observados no JSON do Yosys. A aba **FSM** destaca o estado atual usando os
valores reais do enum, inclusive quando a maquina esta dentro de um submodulo.

Os blocos internos usam dimensoes compactas para nao competir visualmente com os
modulos do usuario. No menu de `input_signal`, **Click action** escolhe entre
editar o valor e incrementa-lo. O incremento respeita a largura do barramento e
volta para zero depois do maior valor. Entradas de um bit sempre alternam entre
zero e um ao clicar no valor central.

Os blocos de entrada, saida e clock recebem automaticamente o nome da primeira
porta a que forem conectados. Esse nome aparece acima do quadrado e na waveform.
Use **Rename...** no menu de contexto para trocar apenas o rotulo visual, sem
alterar a instancia usada na sintese.

O projeto procura primeiro por uma instalacao nativa de `yosys`. Se ela nao
existir, usa o ambiente isolado `.tools/yowasp-env`, que contem a distribuicao
WebAssembly do Yosys. O interpretador atual cobre operadores combinacionais,
multiplexadores e os flip-flops mais comuns gerados por `always_ff`. Celulas de
memoria especiais e primitivas de fabricante devem ser adicionadas ao motor
quando esses casos entrarem no escopo do aplicativo.

Antes da sintese, o RTL Explorer segue as instancias para incluir os modulos dos
quais o bloco depende. Pacotes SystemVerilog sao carregados uma unica vez. Para
frontends que nao aceitam `import pacote::*` dentro do modulo, copias temporarias
qualificam os simbolos como `pacote::simbolo`; os arquivos originais nao sao
alterados.
