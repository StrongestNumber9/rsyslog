#!/bin/bash
# This file is part of the rsyslog project, released under ASL 2.0

# uncomment for debugging support:
. ${srcdir:=.}/diag.sh init
# start up the instances
#export RSYSLOG_DEBUG="debug nostdout noprintmutexaction"
export RSYSLOG_DEBUGLOG="$RSYSLOG_DYNNAME.receiver.debuglog"
generate_conf
export PORT_RCVR="$(get_free_port)"
add_conf '
global(
	defaultNetstreamDriverCAFile="'$srcdir/testsuites/x.509/ca.pem'"
	defaultNetstreamDriverCertFile="'$srcdir/testsuites/x.509/client-cert.pem'"
	defaultNetstreamDriverKeyFile="'$srcdir/testsuites/x.509/client-key.pem'"
	defaultNetstreamDriver="gtls"
#	debug.whitelist="on"
#	debug.files=["nsd_ossl.c", "tcpsrv.c", "nsdsel_ossl.c", "nsdpoll_ptcp.c", "dnscache.c"]
)

module(	load="../plugins/imtcp/.libs/imtcp"
	StreamDriver.Name="gtls"
	StreamDriver.Mode="1"
	StreamDriver.AuthMode="x509/certvalid"
	StreamDriver.PermitExpiredCerts="off"
	)
input(	type="imtcp"
	port="'$PORT_RCVR'" )

action(type="omfile" file="'$RSYSLOG_OUT_LOG'")
'
startup
export RSYSLOG_DEBUGLOG="$RSYSLOG_DYNNAME.sender.debuglog"
#valgrind="valgrind"
generate_conf 2
export TCPFLOOD_PORT="$(get_free_port)" # TODO: move to diag.sh
add_conf '
global(
	defaultNetstreamDriverCAFile="'$srcdir/testsuites/x.509/ca.pem'"
	defaultNetstreamDriverCertFile="'$srcdir/testsuites/x.509/client-expired-cert.pem'"
	defaultNetstreamDriverKeyFile="'$srcdir/testsuites/x.509/client-expired-key.pem'"
	defaultNetstreamDriver="gtls"
)

# Note: no TLS for the listener, this is for tcpflood!
$ModLoad ../plugins/imtcp/.libs/imtcp
$InputTCPServerRun '$TCPFLOOD_PORT'

# set up the action
$ActionSendStreamDriverMode 1 # require TLS for the connection
$ActionSendStreamDriverAuthMode anon
*.*	@@127.0.0.1:'$PORT_RCVR'
' 2
startup 2

# now inject the messages into instance 2. It will connect to instance 1,
# and that instance will record the data.
tcpflood -m1 -i1
sleep 5 # make sure all data is received in input buffers
# shut down sender when everything is sent, receiver continues to run concurrently
shutdown_when_empty 2
wait_shutdown 2
# now it is time to stop the receiver as well
shutdown_when_empty
wait_shutdown

content_check "not permitted to talk to peer, certificate invalid: certificate expired"

unset PORT_RCVR # TODO: move to exit_test()?
exit_test
