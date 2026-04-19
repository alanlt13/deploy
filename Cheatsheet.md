# Cheatsheet

## tmux

```bash
tmux new -s claude       # create new named session
tmux attach -t claude    # attach to existing session
tmux ls                  # list sessions
# Ctrl+b  then  d        # detach (leave session running)
```

## Modern CLI tools — old vs new

| New        | Replaces    | What it does                                  |
|------------|-------------|-----------------------------------------------|
| `rg`       | `grep -r`   | Ripgrep — fast recursive content search       |
| `fd`       | `find`      | Simpler, faster file finder                   |
| `bat`      | `cat`       | Cat with syntax highlighting + paging         |
| `eza`      | `ls`        | Modern ls with colors, icons, git status      |
| `zoxide`   | `cd`        | Jump to frequent dirs: `z proj` instead of cd |
| `fzf`      | (none)      | Fuzzy finder — pipe anything, Ctrl+R history  |
| `btop`     | `top`/`htop`| Prettier, richer process/resource monitor     |
| `ncdu`     | `du`        | Interactive disk usage explorer               |

### Quick usage

```bash
rg "pattern"             # search cwd recursively
fd name                  # find files matching name
bat file.py              # view file with highlighting
eza -la --git            # detailed listing w/ git status
z foo                    # cd to best-matching frecent dir
ctrl+r                   # fzf history search (if integrated)
btop                     # live system monitor
ncdu /var                # explore disk usage under /var
```
