{ pkgs ? import <nixpkgs> {} }:

let
  display = "70";
  sxhkdrc = pkgs.writeText "sxhkdrc" ''
    alt + a
      ./bspc desktop -l next
  '';
  bspwmrc = pkgs.writeShellScript "bspwmrc" ''
    ./bspc config normal_border_color '#30302f'
    ./bspc config active_border_color '#9e8e7e'
    ./bspc config focused_border_color '#906ef5'

    ./bspc config border_width 4
    ./bspc config bottom_padding 48

    ./bspc config ignore_ewmh_fullscreen all
    ./bspc config automatic_scheme alternate
    ./bspc config split_ratio 0.52
    ./bspc config borderless_monocle true
    ./bspc config gapless_monocle true

    ./bspc config pointer_motion_interval 30

    ./bspc config remove_disabled_monitors true
    ./bspc config remove_unplugged_monitors true

    ./bspc wm --adopt-orphans
  '';
in pkgs.mkShell {
  buildInputs = with pkgs; with xorg; [
    x11vnc openssl
    libxcb libXinerama xcbutil xcbutilkeysyms xcbutilwm
  ];
  shellHook = ''
    export TERM="xterm-256color"
    export DISPLAY=":${display}"
    export BSPWM_SOCKET="$(mktemp -u)"

    function run_wm() {
      make debug && ./bspwm -c ${bspwmrc}
    }

    function get_id() {
      ${pkgs.xdotool}/bin/xdotool getmouselocation | grep -oP 'window:\K\d*'
    }
    export -f get_id

    function bspc() { ./bspc "$@"; }
    export -f bspc

    ${pkgs.xlibs.xorgserver}/bin/Xvfb "$DISPLAY" -screen 0 960x720x24 &> /dev/null &
    Xvfb_PID=$!

    while ! ${pkgs.xorg.xdpyinfo}/bin/xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
      sleep 0.1s
    done

    ${pkgs.x11vnc}/bin/x11vnc -display $DISPLAY -bg -forever -nopw -quiet -listen localhost -xkb &>/dev/null &
    x11vnc_PID=$!

    _TMP_HOME="$(mktemp -d)"

    ${pkgs.sxhkd}/bin/sxhkd -c ${sxhkdrc} &
    sxhkd_PID=$!

    # We need to launch our test programs within bspwm,
    # otherwise `bspc wm --adopt-orphans` doesn't work
    make debug
    ./bspwm -c ${bspwmrc} &
    bspwm_PID=$!

    # Wait for the bspwm socket to become available
    while [[ ! -S "$BSPWM_SOCKET" ]]; do
      sleep 0.1s
    done

    HOME="$_TMP_HOME" ${pkgs.xterm}/bin/xterm &>/dev/null &
    xterm_PID=$!
    HOME="$_TMP_HOME" ${pkgs.chromium}/bin/chromium &>/dev/null &
    chromium_PID=$!

    # HACK: we need to wait for xterm and chromium to show up before killing bspwm
    sleep 1s && kill -TERM $bspwm_PID

    ${pkgs.xorg.xsetroot}/bin/xsetroot -solid gray

    function handle_exit() {
      kill -TERM $sxhkd_PID &>/dev/null
      kill -TERM $xterm_PID &>/dev/null
      kill -TERM $chromium_PID &>/dev/null
      kill -TERM $x11vnc_PID &>/dev/null
      kill -TERM $Xvfb_PID &>/dev/null
    }

    trap handle_exit EXIT
  '';
}
