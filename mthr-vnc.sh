#!/usr/bin/env bash
# Open a Mount Thor remote desktop in the bundled VNC viewer.
#
# `mthr vm desktop` and `mthr bm desktop` do not launch a viewer themselves on
# Linux — that path is macOS-only upstream. On Linux they print
#
#     Desktop URI: vnc://127.0.0.1:<port>
#
# and then hold the tunnel open until you interrupt them, leaving you to bring
# your own client. This wrapper is that client: hand it the URI (or just the
# port) from a second terminal and it connects through the bundled viewer.
#
# Deliberately thin. `mthr bm desktop` prints one-shot Screen Sharing
# credentials on its own stdout, so the tunnel has to stay in a terminal you
# can read rather than being backgrounded by a helper.
set -euo pipefail

viewer=${MTHR_VNC_VIEWER:-@vncviewer@}

usage() {
  cat <<'USAGE'
usage: mthr-vnc <vnc://host:port | host:port | port> [viewer args...]

Connect the bundled VNC viewer to a Mount Thor desktop tunnel.

Start the tunnel in another terminal and leave it running. On Linux the
--no-browser flag is what keeps it open; without it the CLI exits and takes
the tunnel with it:

    mthr bm desktop <name> --local-port 5999 --no-browser

It prints the session's Screen Sharing username and password, then
`vnc://127.0.0.1:5999`. Connect from this terminal:

    mthr-vnc 5999
    mthr-vnc vnc://127.0.0.1:5999    # same thing, pasted

The viewer will prompt for those credentials. To skip the prompt, pass them
through the environment (never the command line, which shows up in `ps`):

    VNC_USERNAME=mt-user VNC_PASSWORD=<printed password> mthr-vnc 5999

Any further arguments are passed through to the viewer unchanged. Set
MTHR_VNC_VIEWER to use a different viewer binary.
USAGE
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
esac

target=${1#vnc://}
target=${target%%/*} # drop any trailing path component
shift

case "$target" in
  '')
    echo "mthr-vnc: empty target" >&2
    exit 2
    ;;
  \[*\]:*) # [::1]:5999
    host=${target%]:*}
    host=${host#\[}
    port=${target##*]:}
    ;;
  \[*\]) # [::1], no port
    echo "mthr-vnc: no port in '$1'; pass vnc://host:port or a bare port" >&2
    exit 2
    ;;
  *:*) # 127.0.0.1:5999
    host=${target%:*}
    port=${target##*:}
    ;;
  *) # bare port
    host=127.0.0.1
    port=$target
    ;;
esac

case "$port" in
  '' | *[!0-9]*)
    echo "mthr-vnc: '$port' is not a port number" >&2
    exit 2
    ;;
esac

# `host::port` (double colon) is the form that means a literal TCP port.
# A single colon would be read as an X display number, and the desktop
# tunnel's port is not always above 5900.
case "$host" in
  *:*) server="[$host]::$port" ;;
  *) server="$host::$port" ;;
esac

exec "$viewer" "$server" "$@"
