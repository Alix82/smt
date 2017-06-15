#!/usr/bin/env perl

package SMT::Agent::Constants;

use strict;
use warnings;


# script that processes jobs
use constant PROCESSJOB 	=> '/usr/lib/SMT/bin/processjob';

# config file for smt server url
use constant SUSEREGISTER_CONF	=> '/etc/SUSEConnect';

# path for job handlers (like softwarepush) 
use constant JOB_HANDLER_PATH	=> '/usr/lib/SMT/bin/job';

# rest path start sequence and rest version
use constant REST_START_SEQ	=> '/=/';
use constant REST_VERSION	=> '1';

# rest path for retriving next job id 
use constant REST_NEXT_JOB	=> REST_START_SEQ.REST_VERSION.'/jobs/@next';

# rest path for job update (trailing slash is important)
use constant REST_UPDATE_JOB	=> REST_START_SEQ.REST_VERSION.'/jobs/';

# rest path for job pickup (trailing slash is important)
use constant REST_GET_JOB	=> REST_START_SEQ.REST_VERSION.'/jobs/';

# log file
use constant LOG_FILE		=> '/var/log/smtclient.log';

# client config file
use constant CLIENT_CONFIG_FILE	=> '/etc/sysconfig/smt-client';

# smt client credenitials file containing guid (SLE11)
use constant CREDENTIALS_FILE	=> '/etc/zypp/credentials.d/NCCcredentials';

# smt client credentials files (SLE10)
use constant DEVICEID_FILE	=> '/etc/zmd/deviceid';
use constant SECRET_FILE	=> '/etc/zmd/secret';

# network location and realm used for authentication
use constant AUTH_NETLOC => 'netloc';
use constant AUTH_REALM => 'realm';


1;
