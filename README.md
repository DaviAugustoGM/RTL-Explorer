# RTL Explorer

Base inicial de uma ferramenta em Tcl/Tk para visualizar, documentar e futuramente simular módulos SystemVerilog.

## Como executar

No Windows, abra o projeto e rode:

```powershell
wish src/main.tcl
```

## MVP implementado

- Tema dark inspirado no Visual Studio Code.
- Barra superior com ações principais.
- Menu `File` com `Open Project`, `Open Files`, `Open Folder`, `Save Project` e `Close Project`.
- `Save Project` grava um arquivo `.rtlex` com arquivos abertos, diagrama, conexões e configurações.
- Barra lateral com ícones para os modos de uso.
- Árvore de projeto com arquivos, módulos, sinais e FSMs detectadas em SystemVerilog.
- Modo Blocos com biblioteca lateral no estilo Logisim.
- Biblioteca com módulos do usuário e blocos internos prontos.
- Canvas central com blocos de módulos SystemVerilog.
- Portas de entrada e saída desenhadas nos blocos.
- Blocos arrastáveis.
- Texto dos blocos ajusta tamanho junto com o zoom.
- Opção `Names` na barra superior para ocultar ou mostrar nomes das portas.
- Blocos da biblioteca podem ser arrastados para o canvas ou adicionados com duplo clique.
- Conexões manuais entre portas por clique.
- Painel de propriedades.
- Console inferior de logs.
- Abas preparadas para diagrama, FSM, simulação e documentação.

## Estrutura

```text
src/
├── main.tcl
├── theme.tcl
├── layout.tcl
├── project_tree.tcl
├── canvas_blocks.tcl
├── canvas_connections.tcl
├── properties_panel.tcl
├── console.tcl
├── sv_parser.tcl
├── fsm_viewer.tcl
├── simulator_view.tcl
└── documentation.tcl
```

Os ícones da barra lateral ficam em `assets/icons/` e foram baixados do conjunto Material Icons.

## Sample

A pasta `sample/` contem dois modulos SystemVerilog simples para testar o software:

- `producer.sv`
- `consumer.sv`

Para testar, use `File > Open Folder` e selecione a pasta `sample`.
