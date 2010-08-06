#!/bin/bash

#
# Usage: $0 [HOST [PORT [TRANSPORT [VOLUME]]]]
#


DEBUG=false

HOST='localhost'
PORT=6996
TYPE='tcp'
NAME='client'
USERNAME=''
PASSWORD=''


conf=/tmp/nagios.glusterfs.vol.$$;
log=/tmp/nagios.glusterfs.log.$$;
pid=/tmp/nagios.glusterfs.pid.$$;
PATH='/bin:/usr/bin:/usr/sbin:/usr/local/sbin:/opt/sbin'
glfs=`which glusterfs`

exitcode=0

while getopts h:p:t:n:u:P: OPTION
do
  case "$OPTION" in
  h)    HOST="${OPTARG}";;
  p)    PORT="${OPTARG}";;
  t)    TYPE="${OPTARG}";;
  n)    NAME="${OPTARG}";;
  u)    USERNAME="${OPTARG}";;
  P)    PASSWORD="${OPTARG}";;
  \?)  print >&2 "Usage: $0 [-h host] [-p port] [-t type] [-n fsname] [-u username] [-P password] ..."
    exit 1;;
  esac
done

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
EOF

if [[ "${USERNAME}" != '' ]]
then
  echo "  option username ${USERNAME}" >> $conf
fi

if [[ "${PASSWORD}" != '' ]]
then
  echo "  option password ${PASSWORD}" >> $conf
fi

cat >> $conf <<EOF
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
    # make really sure the process exits, otherwise subsequent checks will fail
    if ps -p `cat $pid`
    then
      kill -9 `cat $pid`
    fi
    rm -rf $conf $log $pid;
    exit $exitcode
}


function watsup()
{
    ans="CRITICAL: Host unreachable"
    exitcode=2

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

    spit_vol;
    glfs;

    watsup;
}


main

