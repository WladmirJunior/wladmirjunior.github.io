# wladmirjunior.github.io

Bootstrap publico das minhas maquinas. So isso: o resto mora no repo privado
`dotfiles` (chezmoi).

```sh
curl -fsSL wladmirjunior.github.io/i | sh        # macOS / Linux
irm wladmirjunior.github.io/w | iex              # Windows
```

| Arquivo | O que faz |
|---|---|
| `i` | macOS/Arch: instala chezmoi + 1Password, espera o SSH agent, `chezmoi init --apply` |
| `w/index.html` | Windows: o mesmo via winget (HTML so pra o Pages servir como texto) |

Os scripts sao curtos de proposito: da pra ler tudo antes de rodar.
