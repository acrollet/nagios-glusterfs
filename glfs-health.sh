#!/bin/bash

#
# Usage: $0 [HOST [PORT [TRANSPORT [VOLUME]]]]
#


DEBUG=true

DEFAULT_HOST=localhost
DEFAULT_PORT=6996
DEFAULT_TYPE=tcp
DEFAULT_NAME=client


conf=/tmp/nagios.glusterfs.vol.$$;
log=/tmp/nagios.glusterfs.log.$$;
pid=/tmp/nagios.glusterfs.pid.$$;
glfs=/usr/sbin/glusterfs;

exitcode=0

function parse_cmd_args()
{
    HOST=$DEFAULT_HOST;
    PORT=$DEFAULT_PORT;
    TYPE=$DEFAULT_TYPE;
    NAME=$DEFAULT_NAME;

    if test "x$1" != "x"; then
        HOST=$1
    fi

    if test "x$2" != "x"; then
        PORT=$2
    fi

    if test "x$3" != "x"; then
        TYPE=$3
    fi

    if test "x$4" != "x"; then
        NAME=$4
    fi
}


function spit_vol()
{
cat > $conf <<EOF

volume client
  type protocol/client
  option remote-host $HOST
  option remote-port $PORT
  option transport-type $TYPE
  option remote-subvolume $NAME
  option ping-timeout 2
end-volume

volume server
  type protocol/server
  option transport-type tcp
  option auth.addr.client.allow *
  subvolumes client
end-volume

EOF

if $DEBUG
then
  cat $conf
fi

}


function glfs()
{
    if $DEBUG
    then
        echo "$glfs -f $conf -l $log -p $pid -LTRACE"
    fi
    $glfs -f $conf -l $log -p $pid -LTRACE
}


function cleanup()
{
    kill -TERM `cat $pid`;
    rm -rf $conf $log $pid;
    exit $exitcode
}


function watsup()
{
    ans="CRITICAL: Host unreachable"

    for i in $(seq 1 10); do
        if grep -iq 'connection refused' $log; then
            ans="CRITICAL: Connection refused"
		exitcode=2
            break
        fi

        if grep -iq 'client: got GF_EVENT_CHILD_UP' $log; then
            ans="CRITICAL: Server Unresponsive"
		exitcode=2
        fi

        if grep -iq 'socket header signature does not match :O' $log; then
            ans="CRITICAL: Unknown service encountered"
		exitcode=2
            break
        fi

        if grep -iq 'client: SETVOLUME on remote-host failed:' $log; then
            ans="CRITICAL: "$(sed -n s/'.*client: SETVOLUME on remote-host failed: '//p $log | tail -n 1);
		exitcode=2
            break
        fi

        if grep -iq 'attached to remote volume' $log; then
            ans="OK"
		exitcode=0
            break
        fi

        sleep 1
    done

    echo $ans
}


function main()
{
    trap cleanup EXIT;

    parse_cmd_args "$@"

    spit_vol;
    glfs;

    watsup;
}


main "$@"

