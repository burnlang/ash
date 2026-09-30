#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
ASH="${ASH:-burni $here/src/main.bn}"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT
export BURN_HOME="$work/home"
export NO_COLOR=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect() {
    printf '%s' "$1" | grep -q -- "$2" || fail "expected \"$2\" in: $1"
}

publish() {
    dir="$work/repos/$1"
    mkdir -p "$dir/src"
    printf '%s' "$2" >"$dir/burn.toml"
    printf '%s' "$3" >"$dir/src/lib.bn"
    if [ ! -d "$dir/.git" ]; then
        git -C "$dir" init -q
    fi
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "$4"
    git -C "$dir" tag "$4"
}

publish fmtlib '[package]
name = "example.com/test/fmtlib"
version = "0.1.0"
kind = "lib"
' 'pub fun shout(text: string): string {
    return upper(text) + "!"
}
' v0.1.0

colors_toml() {
    printf '[package]\nname = "example.com/test/colors"\nversion = "%s"\nkind = "lib"\n\n[dependencies]\n"example.com/test/fmtlib" = { version = "^0.1", git = "file://%s/repos/fmtlib" }\n' "$1" "$work"
}

publish colors "$(colors_toml 1.0.0)" 'import "example.com/test/fmtlib"

pub fun paint(text: string): string {
    return "red " + shout(text)
}
' v1.0.0
publish colors "$(colors_toml 1.1.0)" 'import "example.com/test/fmtlib"

pub fun paint(text: string): string {
    return "blue " + shout(text)
}
' v1.1.0
publish colors '[package]
name = "example.com/test/colors"
version = "2.0.0"
kind = "lib"
' 'pub fun paint(text: string): string {
    return "v2 " + text
}
' v2.0.0

cd "$work"
$ASH init example.com/test/app >/dev/null
cd app
cat >src/main.bn <<'BN'
import "example.com/test/colors"

fun main() {
    print(paint("hi"))
}
BN

out="$($ASH install "example.com/test/colors@^1.0" --git "file://$work/repos/colors")"
expect "$out" "Added example.com/test/colors v1.1.0"
expect "$out" "example.com/test/fmtlib v0.1.0"
grep -q '"example.com/test/colors" = { version = "^1.0", git = ' burn.toml || fail "burn.toml was not updated"
grep -q 'name = "example.com/test/fmtlib"' burn.lock || fail "burn.lock is missing the indirect package"
[ "$(burn run)" = "blue HI!" ] || fail "the app did not run with the package"

out="$($ASH install)"
expect "$out" "2 packages ready"

rm -rf "$BURN_HOME/packages"
$ASH install >/dev/null
[ "$(burn run)" = "blue HI!" ] || fail "reinstalling from burn.lock did not restore the packages"

out="$($ASH list)"
expect "$out" "example.com/test/colors v1.1.0"
expect "$out" "example.com/test/fmtlib v0.1.0"

out="$($ASH install example.com/test/colors@=1.0.0 --git "file://$work/repos/colors")"
expect "$out" "Added example.com/test/colors v1.0.0"
[ "$(burn run)" = "red HI!" ] || fail "pinning an older version did not work"

sed 's/=1.0.0/^1.0/' burn.toml >burn.toml.new && mv burn.toml.new burn.toml
out="$($ASH update)"
expect "$out" "Updated example.com/test/colors v1.0.0 -> v1.1.0"

out="$($ASH install example.com/test/colors@2 --git "file://$work/repos/colors")"
expect "$out" "v2.0.0"
[ "$(burn run)" = "v2 hi" ] || fail "the major update did not run"
if grep -q fmtlib burn.lock; then
    fail "the unused indirect package stayed in burn.lock"
fi

if $ASH install example.com/test/colors@^9 --git "file://$work/repos/colors" 2>"$work/err"; then
    fail "an impossible version was accepted"
fi
expect "$(cat "$work/err")" "no version of example.com/test/colors matches"
expect "$(cat "$work/err")" "available: v1.0.0, v1.1.0, v2.0.0"

if $ASH install colors 2>"$work/err"; then
    fail "a bare name was accepted"
fi
expect "$(cat "$work/err")" "github.com/<owner>/colors"

cat >>burn.toml <<'TOML'
greet = "echo hello"
TOML
[ "$($ASH greet | tail -n 1)" = "hello" ] || fail "a script did not run without the run command"
[ "$($ASH run greet world | tail -n 1)" = "hello world" ] || fail "script arguments were not passed"

out="$($ASH remove example.com/test/colors)"
expect "$out" "Removed example.com/test/colors"
if grep -q colors burn.toml; then
    fail "remove left the dependency in burn.toml"
fi

mkdir -p ../mylib/src
printf '[package]\nname = "example.com/test/mylib"\nkind = "lib"\n' >../mylib/burn.toml
printf 'pub fun paint(text: string): string {\n    return "local " + text\n}\n' >../mylib/src/lib.bn
sed 's/test\/colors/test\/mylib/' src/main.bn >src/main.new && mv src/main.new src/main.bn
out="$($ASH install ../mylib)"
expect "$out" "Added example.com/test/mylib"
grep -q '"example.com/test/mylib" = { path = "../mylib" }' burn.toml || fail "a path dependency was not recorded"
[ "$(burn run)" = "local hi" ] || fail "the path dependency did not run"

game="$work/repos/game"
mkdir -p "$game/src"
printf '[package]\nname = "example.com/test/game"\nversion = "1.0.0"\nkind = "app"\ntarget = "bvm"\n' >"$game/burn.toml"
printf 'pub fun score(points: int): int {\n    return points * 10\n}\n\nfun main() {\n    print("score", score(3))\n}\n' >"$game/src/main.bn"
git -C "$game" init -q
git -C "$game" add -A
git -C "$game" commit -q -m game
git -C "$game" tag v1.0.0
out="$($ASH install example.com/test/game --git "file://$game")"
expect "$out" "Added example.com/test/game v1.0.0"
cat >src/main.bn <<'BN'
import "example.com/test/game.bvmc"

@Inject(target: "score", at: "return")
fun doubled(points: int, result: int): int {
    return result * 2
}
BN
[ "$(burn run)" = "score 60" ] || fail "a mixin on an app installed as a package did not apply"

cd "$work"
$ASH init example.com/test/bvmtool --target bvm >/dev/null
out="$($ASH install -g ./bvmtool)"
expect "$out" "(bvm)"
[ "$("$BURN_HOME/bin/bvmtool")" = "Hello from bvmtool!" ] || fail "the bvm app installed as a command did not run"

cd "$work"
$ASH init example.com/test/tool >/dev/null
out="$($ASH install -g ./tool)"
expect "$out" "Installed example.com/test/tool"
[ "$("$BURN_HOME/bin/tool")" = "Hello from tool!" ] || fail "the installed command did not run"
expect "$($ASH list -g)" "example.com/test/tool"
$ASH remove -g example.com/test/tool >/dev/null
[ ! -e "$BURN_HOME/bin/tool" ] || fail "remove -g left the command"

printf 'ash end-to-end tests passed\n'
