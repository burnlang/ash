<p align="center">
    <img src="https://raw.githubusercontent.com/burnlang/burn/master/assets/logo.svg" alt="Burn logo" width="128">
</p>

# ash

ash is the package manager for [Burn](https://github.com/burnlang/burn), written in Burn itself.

A package is any git repository with a `burn.toml` at the top. It is named after where it lives, like
`github.com/owner/project`, so there is nothing to register: push your code, tag a version, and everyone can install
it.

```sh
ash init github.com/you/hello        # a new native app (add --lib for a library, --target js|bvm|bar)
cd hello
ash install github.com/you/colors    # add a package
ash start                            # run it
ash build                            # build it into build/
```

## Install

ash comes with the Burn toolchain:

```sh
curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh
```

To build it yourself, with Burn installed:

```sh
git clone https://github.com/burnlang/ash && cd ash
burn build && cp build/ash ~/.burn/bin/
```

## Commands

| Command | What it does |
| --- | --- |
| `ash init <name>` | create a project (`--lib`, `--target native\|js\|bvm\|bar`) |
| `ash install` | install everything in `burn.toml`, exactly as `burn.lock` pins it |
| `ash install <name>[@version]` | add a package; `--git <url>` installs from another address |
| `ash install ../path` | add a local package by path |
| `ash remove <name>` | remove a package |
| `ash update [name]` | move packages to the newest versions `burn.toml` allows |
| `ash sync` | refresh the package index, then install everything in `burn.toml`; editors run it to reload a project |
| `ash list` | show the installed packages as a tree |
| `ash run <script> [args]` | run a script from `burn.toml` |
| `ash <script>` | the same, without `run` |
| `ash build`, `ash start`, `ash test` | run the script of that name, or build, run or test the project |
| `ash check`, `ash fmt` | type-check the project, or format all of its files |
| `ash install -g <name\|path>` | install an app as a command in `~/.burn/bin` |
| `ash remove -g <name>`, `ash list -g` | manage installed commands |
| `ash search [words]` | search the [ash index](https://github.com/burnlang/ash-index) |
| `ash info <name>` | show the versions of a package |
| `ash publish [--tag]` | check that others can install this project, and tag the version |

## burn.toml

```toml
[package]
name = "github.com/you/hello"
version = "0.1.0"
kind = "app"            # "app" or "lib"
target = "native"       # what `burn build` makes: "native", "js", "bvm" or "bar"
main = "src/main.bn"

[dependencies]
"github.com/you/colors" = "^1.2"
"github.com/you/local" = { path = "../local" }
"example.org/team/tool" = { version = "^0.3", git = "https://example.org/team/tool.git" }

[scripts]
dev = "burni src/main.bn"
release = "burnc src/main.bn -o build/hello"
```

Versions are git tags such as `v1.2.0`:

| Written | Allows |
| --- | --- |
| `"^1.2"` | `1.2.0` up to, not including, `2.0.0` (what `ash install` writes) |
| `"~1.2"` | `1.2.x` |
| `"=1.2.3"` | exactly `1.2.3` |
| `">=1.2"` | `1.2.0` and anything newer |
| `"*"` | the newest version, or the newest commit when there are no tags |
| `"main"` | the newest commit on a branch |
| `"#1a2b3c"` | one exact commit |

`burn.lock` records the exact commit of every package, including the packages your packages need. Commit it, and
`ash install` gives everyone the same code. Downloads are cached in `~/.burn/packages`, so a package is only
fetched once per version.

## Using a package

```burn
import "github.com/you/colors"

print(paint("hello"))
```

Importing a package loads its `main` file. `import "github.com/you/colors/extra"` loads `src/extra.bn` from it.

## Workspaces

In a [workspace](https://github.com/burnlang/burn/blob/master/docs/tooling/packages.mdx#workspaces), ash works on the
whole workspace at once:

- `ash install`, `ash update`, `ash remove` and `ash sync` keep one `burn.lock` at the workspace root for every member.
- Run `ash install <name>` inside the member that needs the package, or pick it with `-p`: `ash -p native install github.com/you/colors`.
- At the root, `ash list` shows every member's packages, and `ash build`, `ash test` and `ash check` work on every member. `-p <member>` picks one.

A member of a workspace can be installed like any other package. `ash install github.com/you/game/common`
downloads the repository `github.com/you/game` and uses its `common` folder. The members it depends on by `path`
are pinned to the same commit.

Apps can be packages too, whatever their target. Import one as source, or as bytecode to change it with mixins:

```burn
import "github.com/you/game.bvmc"

@Inject(target: "score", at: "return")
fun doubled(points: int, result: int): int {
    return result * 2
}
```

`ash install -g` builds an app for its own target: a native executable, a runnable `.bar` archive for
`target = "bvm"` or `"bar"`, or a Node.js script with a small launcher for `target = "js"`.

## Development

```sh
burn run tests/main.bn     # unit tests
sh tests/e2e.sh            # end-to-end tests with local git repositories
```

## License

[GNU General Public License v3.0](LICENSE)
