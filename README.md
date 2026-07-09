# RTL Explorer

RTL Explorer e uma ferramenta grafica em Tcl/Tk para abrir projetos Verilog/SystemVerilog, visualizar modulos como diagramas de blocos, analisar maquinas de estado e testar modulos sintetizaveis com simulacao interativa.

O objetivo do projeto e aproximar o fluxo de RTL de uma experiencia visual parecida com ferramentas como Logisim/Falstad, mas usando modulos reais em Verilog/SystemVerilog.

## Recursos principais

- Abre arquivos `.sv`, `.v` ou pastas completas de RTL.
- Salva e reabre projetos `.rtlex` com arquivos, blocos, conexoes, configuracoes e layout.
- Detecta modulos, portas, larguras de barramento, parametros simples e instancias nomeadas ou posicionais.
- Monta diagramas de blocos arrastaveis a partir dos modulos do usuario.
- Permite conexoes manuais, conexoes automaticas e conexoes por faixa de bits.
- Possui blocos internos para entrada, saida, clock, constantes, logica e armazenamento.
- Permite autoconectar blocos de entrada/saida aos modulos selecionados.
- Suporta nomes editaveis, formatos binario/decimal/hexadecimal e mapeamento de valores para texto.
- Mostra waveforms ao vivo no proprio modo de diagrama.
- Permite pausar, continuar, parar e executar simulacao pelo diagrama.
- Exporta diagramas de blocos e maquinas de estado para PDF.
- Detecta e desenha maquinas de estado a partir do codigo RTL.
- Permite mover estados, textos de transicao e ajustar visual da FSM.
- Suporta loops inferidos para transicoes implicitas de permanencia no mesmo estado.
- Tem instalador Windows offline e instalacao local no Linux sem precisar de sudo.

## Como executar

### Windows

Para usuario final, baixe e execute o instalador:

```text
RTL-Explorer-Setup.exe
```

O instalador inclui Tcl/Tk, Yosys, sv2v, Icarus Verilog e o compilador C++ usado pelo motor CXXRTL.

Durante o desenvolvimento, tambem e possivel executar direto pelo codigo:

```powershell
wish src/main.tcl
```

Ou, a partir da nova pasta do projeto:

```powershell
cd D:\RTL_EXP
wish src\main.tcl
```

### Linux

Instalacao local, sem `sudo`:

```sh
make install
```

Depois execute pelo menu do sistema ou pelo terminal:

```sh
rtl-explorer
```

Para rodar direto do codigo, se `wish` estiver instalado:

```sh
wish src/main.tcl
```

## Gerar o instalador Windows

A partir da raiz do projeto:

```powershell
cd D:\RTL_EXP
powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-installer.ps1
```

O instalador sera gerado em:

```text
dist\windows\RTL-Explorer-Setup.exe
```

Se ja houver ferramentas baixadas em `D:\RTL_EXP_tools`, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-installer.ps1 -ReuseLocalTools
```

## Fluxo basico de uso

1. Abra uma pasta ou arquivos com `File > Open Folder` ou `File > Open Files`.
2. Va para o modo `Blocos`.
3. Arraste modulos da biblioteca lateral para o canvas.
4. Conecte portas manualmente ou use `Auto Connect`.
5. Adicione blocos de entrada, saida e clock quando quiser simular.
6. Use `Build and Run` para sintetizar e iniciar a simulacao.
7. Use `Run`, `Pause`, `Stop` e `Step` para controlar a simulacao.
8. Ative `Waveforms` para acompanhar sinais em tempo real.

## Simulacao

O RTL Explorer usa ferramentas externas para transformar o RTL em algo executavel:

- `sv2v`: converte SystemVerilog sintetizavel para Verilog quando necessario.
- `Yosys`: sintetiza o RTL e gera netlists.
- `CXXRTL`: motor padrao para modulos sintetizaveis.
- `Icarus Verilog`: motor alternativo para cenarios mais proximos de simulacao Verilog.
- Simulador Python interno: fallback simples para alguns circuitos pequenos.

A simulacao principal foi pensada para o diagrama de blocos: o usuario conecta blocos de entrada, saida e clock ao modulo que deseja testar.

## Maquinas de estado

O modo `FSM` mostra maquinas de estado detectadas no codigo. Ao selecionar um modulo ou uma FSM no Explorer, o visualizador abre a maquina correspondente.

Recursos do modo FSM:

- Estados em formato circular.
- Transicoes curvas.
- Textos de condicao moviveis.
- Estado especial `ANY STATE` para transicoes globais, como reset.
- Opcao `Inferred Loops` para mostrar permanencia implicita no mesmo estado.
- Zoom e deslocamento do campo de visao.
- Exportacao para PDF.

## Estrutura do projeto

```text
assets/       Icones e recursos visuais.
dist/         Saida de builds e instaladores gerados.
packaging/    Scripts de instalacao e empacotamento Windows/Linux.
sample/       Projetos e modulos pequenos para teste.
scripts/      Scripts auxiliares de verificacao.
src/          Codigo principal do RTL Explorer.
tests/        Testes automaticos.
```

Arquivos importantes em `src/`:

```text
main.tcl                  Entrada principal do programa.
layout.tcl                Janela, menus, abas e barra superior.
project_tree.tcl          Explorer lateral e biblioteca de blocos.
canvas_blocks.tcl         Desenho e interacao dos blocos.
canvas_connections.tcl    Fios, conexoes, snap e auto connect.
sv_parser.tcl             Leitura de Verilog/SystemVerilog.
fsm_viewer.tcl            Visualizador de maquinas de estado.
simulation_model.tcl      Preparacao de top modules e sintese.
simulation_backends.tcl   Motores de simulacao.
simulator_view.tcl        Tela e controles de simulacao.
pdf_export.tcl            Exportacao de diagramas para PDF.
toolchain.tcl             Localizacao das ferramentas externas.
```

## Samples

A pasta `sample/` contem exemplos simples para testar rapidamente:

- `producer.sv`
- `consumer.sv`
- `vending_machine.sv`

Para testar, use `File > Open Folder` e selecione a pasta `sample`.

## Arquivos gerados

Durante build, simulacao ou empacotamento, algumas pastas podem ser criadas:

```text
.rtl_explorer_build/   Arquivos temporarios de sintese/simulacao.
.tools/                Ferramentas locais baixadas para desenvolvimento.
dist/                  Instaladores, downloads e staging de empacotamento.
```

Esses arquivos nao sao o codigo principal do programa.

## Licencas e terceiros

As ferramentas externas usadas no empacotamento estao documentadas em:

```text
packaging/THIRD_PARTY.md
```
