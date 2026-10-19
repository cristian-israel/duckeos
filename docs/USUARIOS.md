# Contas da máquina

O DuckeOS tem uma conta principal e pode ter outras na mesma instalação. A principal fica em `local-config.nix`, que o Git ignora. As outras ficam em `local-users.json`, também ignorado, e o comando `ducke user` é quem grava esse arquivo.

O `home.nix` descreve a área de trabalho comum e continua no repositório. Um rebuild aplica o sistema inteiro e o `home.nix` em cada conta declarada. A conta principal é a dona do clone do repositório. As outras não recebem outro clone: o home de cada uma é `/home/<username>`, salvo quando o home diz outro caminho.

Com uma conta só, o login automático entra nela. Com duas ou mais, o SDDM mostra o seletor.

Os servidores SSH cadastrados nesta máquina estão em [SRV.md](SRV.md).

## Conta principal

É o `ducke.local.username` do `local-config.nix`. Ela existe sempre e entra no grupo `wheel`, então tem `sudo`. Também entra em `networkmanager`, `i2c`, `docker`, `uinput`, `input`, `libvirtd`, `kvm` e `srv`.

O nome e o e-mail do Git (`gitName` e `gitEmail`) valem só para ela. O diretório do repositório é `repositoryDirectory`. O comando `ducke user` não cria, não edita e não remove essa conta. `ducke user -l` só a mostra. `ducke user list` faz o mesmo.

Exceções de programa da principal, se houver, ficam no mesmo `ducke.local`, fora das contas adicionais:

```nix
extraPackages = [ pkgs.obsidian ];
excludePackages = [ "spotify" ];
```

`extraPackages` exige que o arquivo comece com `{ pkgs, lib, ... }:`.

## Contas adicionais

`ducke user` grava cada conta em `local-users.json`. O rebuild lê esse arquivo. Um bloco `users = [ ... ]` escrito em `local-config.nix` faz o comando parar, para não haver duas listas.

| Campo | Efeito |
| --- | --- |
| `username` | Nome Unix: começa com letra minúscula ou `_`, e segue com minúsculas, números, `_` ou `-`. Não pode repetir a conta principal. |
| `fullName` | Nome de exibição. Vazio repete o `username`. |
| `homeDirectory` | Diretório home. Vazio usa `/home/<username>`. |
| `excludePackages` | Chaves removidas da lista comum do `home.nix`, por exemplo `code-cursor` ou `spotify`. |
| `extraPackages` | Nomes de pacotes Nix acrescentados só nessa conta, por exemplo `obsidian`. |
| `extraGroups` | Grupos além de `input` e `uinput`. O grupo `srv` libera os servidores SSH cadastrados. |
| `passwordless` | Entra no SDDM sem digitar senha. |
| `passwordFile` | Caminho do hash da senha, em `/var/lib/duckeos/passwords/`. O hash não entra no JSON nem na Nix Store. |

O que continua de fora:

- Shell. Toda conta usa Fish.
- Dono do repositório, identidade Git ou troca da conta principal.
- Uma lista inteira de programas no lugar do `home.nix`. Dá para acrescentar ou tirar itens, não para substituir a base.
- Os grupos básicos `input` e `uinput`. Eles vêm sempre. O comando só soma os outros.

## Permissões

Sem grupos extras, a conta fica com permissão baixa:

- `input` e `uinput` cobrem teclado, mouse e controle.
- A internet funciona pela conexão que o sistema já estabeleceu. A conta não liga, desliga nem edita a rede.

Isso não inclui `sudo`, Docker, máquina virtual nem o grupo `networkmanager`. A ausência de `wheel` já deixa a conta sem `sudo`.

No `ducke user add` e no `ducke user edit`, o espaço marca o grupo e o enter confirma. Os grupos são `wheel`, `networkmanager`, `docker`, `libvirtd`, `kvm`, `i2c` e `srv`. Dá para marcar só uma parte, por exemplo Docker sem `sudo`. A conta principal já entra em `srv`. Uma conta adicional sem esse grupo não usa `ducke srv`. Ter `wheel` não libera os servidores.

A mesma tela lista programas da área de trabalho que podem sair da conta, como o Cursor ou o Spotify. Pacotes Nix que não estão nessa lista, como `obsidian`, entram no campo de pacotes a mais.

## Senha

Há dois modos. Os dois valem na criação e, depois, na edição.

- Definir senha. O comando pede a senha duas vezes, sem mostrar, e grava só o hash em `/var/lib/duckeos/passwords/<username>`. A senha não vai na linha de comando, para não ficar no histórico.
- Entrar sem senha. No SDDM a conta abre sem digitar nada. SSH, `su` e `sudo` continuam sem aceitar isso.

Na edição, a terceira opção é manter a senha como está. Um rebuild posterior não troca a senha de uma conta que já existe. Quem altera a senha é o próprio `ducke user`.

## Comandos

Só a conta principal, ou root, executa estes comandos. `user` sozinho não existe.

```bash
ducke user -h
ducke user -l
ducke user add
ducke user edit outro
ducke user remove outro
```

`ducke user` sem argumentos, e `ducke user -h`, mostram a ajuda. `ducke user list` faz o mesmo que `ducke user -l`. A primeira linha da lista é o cabeçalho das colunas: tipo, usuário, nome, home, login e grupos.

`add` e `edit`, num terminal e sem flags, perguntam o resto. Sem terminal, as flags cobrem o mesmo caminho. `remove` tira a conta e o hash. Os arquivos do home ficam no disco. `--remove-home` apaga o diretório depois do rebuild, e no terminal pede para digitar o nome. A conta principal não entra nesse comando. Se a pessoa estiver em uma sessão, a remoção para.

```bash
ducke user add outro --group wheel --exclude spotify --package obsidian --no-password
ducke user edit outro --password
ducke user remove outro --remove-home
```

`--password` sempre pede a senha neste terminal. `--no-apply` só grava o registro. `--yes` pula a confirmação. Ao terminar, o comando pergunta se aplica com o `rebuild`.

No próximo boot o SDDM lista as contas. O Super+L continua trancando só a sessão de quem está na tela. Trocar de pessoa é voltar ao SDDM.
