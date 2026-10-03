## v0.2.0 (2026-10-03)

### Feat

- Move to, senha do RDP e confirmações de exclusão viram cartões flutuantes (Popover, sem empurrar a lista; Move to como árvore de pastas) e o popup se adapta a telas baixas (busca/breadcrumb e botões fixos, só a lista rola, scroll acompanha o teclado, os cartões e o campo focado, dica de atalhos some sem espaço)
- menu ⋯ das conexões e pastas vira um menu de contexto flutuante (uma ação por linha com ícone e atalho de teclado, Delete separado embaixo; abre sobre a lista sem empurrar os itens e o popup cresce se ele passar do fim)
- organiza as conexões em pastas, navegadas como num gerenciador de arquivos (breadcrumb, subpastas, criar/renomear/excluir pasta, Move to, seletor de pasta no formulário, ~/.ssh/config como pasta somente-leitura); fix: Enter num campo de texto vazava para o painel e conectava a linha sob o cursor (ex.: salvar o formulário com Enter)
- cartão "Install what you need" na tela de primeiro uso abre o Setup (a engrenagem sozinha passava despercebida num PC novo)
- folha de revisão no lugar do terminal (comandos visíveis, uma senha via pkexec, progresso ao vivo, desfazer/repetir) e tela Setup na engrenagem para instalar/remover tudo o que o plugin usa
- RDP abre com a barra de conexão estilo Windows (xfreerdp3 /floatbar), com opção de voltar ao sdl-freerdp3 nativo; fix: opções RDP desligadas (clipboard) eram ignoradas porque o jq tratava false como ausente
- sessões ativas com Show/Disconnect, aviso com os atalhos de saída do FreeRDP/TigerVNC e RDP sem capturar o teclado por padrão (atalhos do Omarchy continuam funcionando)
- nova interface com abas Connect e This machine, formulário com rótulos e teste de porta, ações na linha selecionada e tela de primeiro uso
- teste de alcance dos servidores, assistente de chave SSH, autorizar chave nesta máquina, derrubar um espectador, modo só visualizar e resumo "depois disso / como desfazer" no terminal
- ações que precisam de sudo abrem um terminal do Omarchy que mostra os comandos exatos, avisa e pede confirmação (tudo, passo a passo ou cancelar) no lugar do pkexec
- seção "This machine" para ligar o servidor SSH (LAN ou só Tailscale, com opção só chaves) e compartilhar a tela via wayvnc, com confirmação antes de toda ação que pede senha de admin
- overlay de conexão rápida por atalho e hosts do ~/.ssh/config no painel e no overlay
- bar widget para salvar e abrir conexões SSH, RDP e VNC, com senhas no GNOME keyring

### Fix

- compartilhamento de tela não subia na segunda vez (socket velho fazia apagar a config antes do wayvnc ler) e RDP sem senha salva travava sem janela (xfreerdp3 pedia credenciais num terminal inexistente): senha pedida no popup/Quick connect, vigia de prompt e Disconnect sem erro falso
- **security**: "Local network" só libera faixas privadas (antes abria para a internet via IPv6), valida hosts/campos antes de chamar os clientes (Via= do TigerVNC, quebras de linha no FreeRDP, opções no ssh -J), bloqueia sequências de escape no terminal de confirmação, drop-in do Require keys lido primeiro e verificado de fato, e dados do plugin só legíveis pelo usuário
- destaque da conexão some quando o mouse sai (hover separado da seleção do teclado)
- menu ⋯ da conexão sempre pode ser fechado (vira ✕ enquanto aberto) e trocar de aba fecha menus e confirmações
- ícone de terminal para SSH (o glifo anterior aparecia como um "SSH" ilegível)

### Refactor

- remove o acesso remoto a esta máquina (servidor SSH, compartilhamento de tela, firewall) e foca o plugin em gerenciar conexões; Setup só com os clientes
- instala pacotes com omarchy pkg add em vez de chamar o pacman direto
