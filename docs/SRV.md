# Servidores SSH

O `ducke srv` abre servidores SSH a partir desta máquina. O Kitty mostra a janela e o Zellij segura a sessão. Nada disso é instalado no servidor. O comando `srv` sozinho não existe, do mesmo modo que `user` sozinho não existe.

O endereço de cada servidor é o nome ou o IP do Tailscale. O login é usuário e senha. A senha não fica no registro, na linha de comando nem no histórico. Ela é digitada no primeiro painel.

As contas que podem usar este comando estão em [USUARIOS.md](USUARIOS.md).

## Registro

Só a conta principal, ou root, cadastra, edita e apaga. O arquivo é `/var/lib/ducke-srv/servers.json`. O diretório fica `root:srv` e modo `0750`. O arquivo fica `root:srv` e modo `0640`. Quem está no grupo `srv` lê. Não escreve. O arquivo não entra no Git e o cadastro não dispara rebuild.

| Campo | Efeito |
| --- | --- |
| `alias` | Apelido do comando. Começa com letra e segue com letras, números, ponto, hífen ou sublinhado. |
| `host` | Nome MagicDNS, IPv4 ou IPv6 do Tailscale. |
| `user` | Usuário remoto. |
| `panes` | Quantidade de terminais na próxima sessão nova. De 1 a 12. O padrão é 4. |

## Quem pode usar

A conta principal entra no grupo `srv` sempre. Uma conta adicional só entra se `srv` estiver em `extraGroups`. Ter `wheel` não libera.

| Conta | O que faz |
| --- | --- |
| Principal | Cadastra, edita, apaga, lista, abre e fecha as próprias sessões. |
| No grupo `srv` | Lista, abre e fecha as próprias sessões. Não altera o registro. |
| Fora do grupo | `ducke srv` recusa. |

Cada conta tem a própria sessão. Fechar a de uma não fecha a da outra. O grupo esconde a lista e trava o comando. Não impede um `ssh` manual de quem já sabe endereço, usuário e senha, porque as contas saem pelo mesmo Tailscale.

## Sessão

Uma sessão por servidor por conta, chamada `ssh-<apelido>`. Duas janelas da mesma pessoa são a mesma sessão. O que se digita numa aparece na outra.

- Fechar a janela deixa a sessão viva, com os mesmos painéis. `ducke srv api` cola nela, sem pedir a senha de novo.
- Bloquear a tela encerra as sessões dessa conta. Na volta, `ducke srv api` abre a quantidade salva e pede a senha.
- Cair a rede, suspender, desligar ou reiniciar mata os SSH. Na volta, a quantidade salva abre de novo e a senha é pedida outra vez. O que estava digitado naqueles terminais não volta.

`ducke srv api 2` grava dois painéis e, se a sessão ainda não existe, abre dois. Se a sessão já está aberta, o número é ignorado e a janela só cola nela. Dentro da sessão, o atalho de painel novo do Zellij entra no mesmo SSH. Fora dela, abre um shell local. Fechar um painel tira só ele. O último encerra a sessão.

O primeiro painel pede a senha. Os outros entram nessa conexão, sem pedir de novo. Dentro de um painel, o uso do PM2 continua o de sempre: `pm2 list`, `pm2 logs nome`, `pm2 restart nome`, `pm2 stop nome`.

## Comandos

`ducke -h` lista os grupos `user` e `srv`. `ducke srv` sem argumentos abre o painel para escolher um servidor. `ducke srv -h` mostra a ajuda.

```bash
ducke srv -l
ducke srv add
ducke srv edit api
ducke srv remove api
ducke srv
ducke srv api
ducke srv api 2
ducke srv pane
ducke srv close api
ducke srv close --all
```

`ducke srv -l` imprime o cabeçalho e as colunas apelido, endereço, usuário e painéis. Sem servidores, o cabeçalho sai mesmo assim, seguido de uma linha dizendo que não há servidores. `ducke srv list` faz o mesmo que `ducke srv -l`.

`add` e `edit`, num terminal e sem flags, perguntam o resto. Sem terminal, as flags cobrem o mesmo caminho. `remove` pede confirmação, encerra a sessão de quem rodou o comando e apaga o registro. As sessões já abertas por outras contas seguem até elas fecharem.

```bash
ducke srv add api --host 100.64.0.12 --user deploy --panes 4
ducke srv edit api --panes 2
ducke srv remove api --yes
```

`--yes` pula a confirmação do `remove`.
