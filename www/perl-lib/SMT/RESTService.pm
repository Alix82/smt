package SMT::RESTService;

use strict;
use warnings;

use APR::Brigade ();
use APR::Bucket ();
use APR::Const     -compile => qw(:error SUCCESS BLOCK_READ);
use Apache2::Filter ();

use APR::Brigade;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::Access ();

use Apache2::Const -compile => qw(OK SERVER_ERROR HTTP_UNAUTHORIZED NOT_FOUND FORBIDDEN AUTH_REQUIRED MODE_READBYTES :log);
use Apache2::RequestUtil;

use XML::Writer;

use SMT::Utils;
use SMT::JobQueue;
use SMT::Job;
use SMT::Client;
use SMT::Product;
use SMT::Patch;
use SMT::Repositories;
use DBI qw(:sql_types);
use Data::Dumper;


#
# the handler for requests to the jobs ressource
#
sub jobs_handler($$)
{
    my $r   = shift || return undef;
    my $dbh = shift || return undef;
    my $path = sub_path($r);
    # username already checked in handler
    my $username = $r->user;

    # jobs (for authenticated client)
    my $reJobs     = qr{^jobs?(/(\@all)?)?$};  # get list of all MY jobs
    my $reJobsNext = qr{^jobs?/\@next$};       # get MY next job
    my $reJobsId   = qr{^jobs?/([\d]+)$};      # get job information (GET) or finish job (PUT)

    # get a job request object
    my $jobq = SMT::JobQueue->new({ 'dbh' => $dbh }) || return undef;

    # map the requests to the functions
    if    ( $r->method() =~ /^GET$/i )
    {
        if    ( $path =~ $reJobs )     { return $jobq->getJobList({ asXML => '', short => 0, GUID => $username }) }
        elsif ( $path =~ $reJobsNext ) { return $jobq->getJob    ({ asXML => '', short => 1, GUID => $username, ID => $jobq->getNextJobID({ GUID => $username }) }) }
        elsif ( $path =~ $reJobsId )   { return $jobq->getJob    ({ asXML => '', short => 1, GUID => $username, ID => $1, retrieve => 1 }) }
        else
        {
            $r->log->error("GET request to unknown jobs interface: $path");
            return undef;
        }
    }
    elsif ( $r->method() =~ /^PUT$/i )
    {
        if ( $path =~ $reJobsId )
        {
            my $c = SMT::Utils::read_post($r);
            return $jobq->finishJob({ GUID => $username, xmldata => $c });
        }
        else { return undef; }
    }
    elsif ( $r->method() =~ /^POST$/i )
    {
        # This request type is not (yet) supported
        # POSTing to the "jobs" interface (which is only used by smt-clients) means "creating a job"
        # It may be implemented later for the "clients" interface (which is for administrator usage).
        $r->log->error("POST request to the jobs interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^DELETE$/i )
    {
        # This request type is not (yet) supported
        # DELETEing to the "jobs" interface (which is only used by smt-clients) means "deleting a job"
        # It may be implemented later for the "clients" interface (which is for administrator usage).
        $r->log->error("DELETE request to the jobs interface. This is not supported.");
        return undef;
    }
    else
    {
        $r->log->error("Unknown request to the jobs interface.");
        return undef;
    }

    return undef;
}


#
# the handler for requests to the clients ressource
#
# Note: this interface is for administrative use only, and not officially supported
#       it is not enabled by default, the admin needs to enable it manually
#       it offers full read-only access to all client data, patchstatus information and the JobQueue
#
sub clients_handler($$)
{
    my $r   = shift || return undef;
    my $dbh = shift || return undef;
    my $path = sub_path($r);
    # username already checked in handler
    my $username = $r->user;

    # read smt.conf to get info about RESTAdminUser
    my $cfg = undef;
    eval {  $cfg = SMT::Utils::getSMTConfig();  };
    if ( $@ || ! defined $cfg )
    {
        $r->log_error("Cannot read the SMT configuration file: ".$@);
        return undef;
    }
    my $RR = 0;
    my $restEnable = $cfg->val('REST', 'enableRESTAdminAccess');
    if ( defined $restEnable && $restEnable =~ /^1$/ )
    {
        my $RAU = $cfg->val('REST', 'RESTAdminUser');
        $RR = ( defined $RAU  &&  $RAU eq $username ) ? 1:0;
        # password checked already in Auth handler
    }

    # if not authenticated as administrator this complete interface will not be available
    unless ($RR)
    {
        $r->log_error("Authentication as administrator failed or administrative interface is disabled.");
        return undef;
    }

    # get a client request object
    my $client = SMT::Client->new({ 'dbh' => $dbh }) || return undef;
    # get a job request object
    my $jobq = SMT::JobQueue->new({ 'dbh' => $dbh }) || return undef;

    # clients
    my $reClients           = qr{^clients?(/(\@all)?)?$};               # get list of all clients
    my $reClientsId         = qr{^clients?/([\w]+)$};                   # get client information
    # clients/jobs
    my $reClientsAllJobs    = qr{^clients?/\@all/jobs?(/(\@all)?)?$};   # get list of jobs of all clients
    my $reClientsIdJobs     = qr{^clients?/([\w]+)/jobs?(/(\@all)?)?$}; # get list of jobs of one client
    my $reClientsIdJobsNext = qr{^clients?/([\w]+)/jobs?/\@next$};      # get next job for one client
    my $reClientsIdJobsId   = qr{^clients?/([\w]+)/jobs?/(\d+)$};       # get job information of one job for one client
    # clients/patchstatus
    my $reClientsIdPatchstatus  = qr{^clients?/([\d\w]+)/patchstatus$}; # get patchstatus info for one client
    my $reClientsAllPatchstatus = qr{^clients?/\@all/patchstatus$};     # get patchstatus info for all clients

    # map the requests to the functions
    if    ( $r->method() =~ /^GET$/i )
    {
        if    ( $path =~ $reClients )              { return $client->getAllClientsInfoAsXML(); }
        elsif ( $path =~ $reClientsId )            { return $client->getClientsInfo({'GUID' => $1, 'asXML' => 'one', 'selectAll' => '' }); }
        elsif ( $path =~ $reClientsAllJobs )       { return $jobq->getAllJobsInfoAsXML(); }
        elsif ( $path =~ $reClientsIdJobs )        { return $jobq->getJobList({ asXML => '', short => 0, GUID => $1, });  }
        elsif ( $path =~ $reClientsIdJobsNext )    { return $jobq->getJob    ({ asXML => '', short => 0, GUID => $1, ID => $jobq->getNextJobID({ GUID => $1 }) }); }
        elsif ( $path =~ $reClientsIdJobsId )      { return $jobq->getJob    ({ asXML => '', short => 0, GUID => $1, ID => $2 }); }
        elsif ( $path =~ $reClientsIdPatchstatus )
        {
            return $client->getClientsInfo( { 'GUID' => $1, 'ID' => '', 'PATCHSTATUS' => '', 'asXML' => 'one' } );
        }
        elsif ( $path =~ $reClientsAllPatchstatus )
        {
            return $client->getClientsInfo( { 'GUID' => '', 'ID' => '', 'PATCHSTATUS' => '', 'asXML' => '' } );
        }
        else
        {
            $r->log->error("GET request to unknown clients interface: $path");
            return undef;
        }
    }
    elsif ( $r->method() =~ /^PUT$/i )
    {
        # This request type is not yet supported for the clients interface
        # Maybe it will be implemented later to be a full REST ressource for the clients information and JobQueue
        $r->log->error("PUT request to the clients interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^POST$/i )
    {
        # This request type is not yet supported for the clients interface
        # Maybe it will be implemented later to be a full REST ressource for the clients information and JobQueue
        $r->log->error("POST request to the clients interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^DELETE$/i )
    {
        # This request type is not yet supported for the clients interface
        # Maybe it will be implemented later to be a full REST ressource for the clients information and JobQueue
        $r->log->error("DELETE request to the clients interface. This is not supported.");
        return undef;
    }
    else
    {
        $r->log->error("Unknown request to the clients interface.");
        return undef;
    }

    return undef;
}


#
# the handler for requests to products resource
#
sub products_handler($$)
{
    my $r = shift || return undef;
    my $dbh = shift || return undef;
    my $path = sub_path($r);

    my $reProducts        = qr{^products?(/(\@all)?)?$}; # get all products
    my $reProductsId      = qr{^products?/(\d+)$};       # get specific product info (GET)
    my $reProductsIdRepos = qr{^products?/(\d+)/repos$}; # get repos of a specific product id

    if ( $r->method() =~ /^GET$/i )
    {
        if ( $path =~ $reProducts )
        {
            return SMT::Product::getAllAsXML($dbh);
        }
        elsif ( $path =~ $reProductsId )
        {
            my $p = SMT::Product::findById($dbh, $1);
            return undef unless defined $p;
            return $p->asXML;
        }
        elsif ( $path =~ $reProductsIdRepos )
        {
            return SMT::Repositories::getProductReposAsXML($dbh, $1);
        }
    }
    elsif ( $r->method() =~ /^PUT$/i )
    {
        $r->log->error("PUT request to the products interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^POST$/i )
    {
        $r->log->error("POST request to the products interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^DELETE$/i )
    {
        $r->log->error("DELETE request to the products interface. This is not supported.");
        return undef;
    }
    else
    {
        $r->log->error("Unknown request to the products interface.");
        return undef;
    }

    return undef;
}

#
# handler for requests to the repos resource
#
sub repos_handler($$)
{
    my $r = shift || return undef;
    my $dbh = shift || return undef;
    my $path = sub_path($r);

    my $reRepos   = qr{^repos?(/(\@all)?)?$};    # get all repos
    my $reReposId = qr{^repos?/(\d+)$};          # get specific repo
    my $rePatches = qr{^repos?/(\d+)/patches$};  # get list of patches of a repo

    if    ( $r->method() =~ /^GET$/i )
    {
        if ( $path =~ $reReposId )
        {
            return SMT::Repositories::getRepositoryAsXML($dbh, $1);
        }
        elsif ($path =~ $rePatches)
        {
            return SMT::Patch::getRepoPatchesAsXML($dbh, $1);
        }
        elsif ( $path =~ $reRepos )
        {
            return SMT::Repositories::getAllReposAsXML($dbh);
        }
        else
        {
            $r->log->error("GET request to unknown repos interface: $path");
            return undef;
        }
    }
    elsif ( $r->method() =~ /^PUT$/i )
    {
        $r->log->error("PUT request to the repos interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^POST$/i )
    {
        $r->log->error("POST request to the repos interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^DELETE$/i )
    {
        $r->log->error("DELETE request to the repos interface. This is not supported.");
        return undef;
    }
    else
    {
        $r->log->error("Unknown request to the repos interface.");
        return undef;
    }

    return undef;
}


#
# handler for requests to the patches resource
#
sub patches_handler($$)
{
    my $r = shift || return undef;
    my $dbh = shift || return undef;
    my $path = sub_path($r);

    my $rePatches   = qr{^patch(es)?(/(\@all)?)?$};    # get all patches
    my $rePatchId   = qr{^patch(es)?/(\d+)$};          # get specific patch

    if    ( $r->method() =~ /^GET$/i )
    {
        if ( $path =~ $rePatchId )
        {
            return SMT::Patch::findById($dbh, $2)->asXML();
        }
        #elsif ( $path =~ $rePatches )
        #{
        #    # we can add a function to return a list of all patches
        #}
        else
        {
            $r->log->error("GET request to unknown patches interface: $path");
            return undef;
        }
    }
    elsif ( $r->method() =~ /^PUT$/i )
    {
        $r->log->error("PUT request to the patch/\$pid interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^POST$/i )
    {
        $r->log->error("POST request to the patch/\$pid interface. This is not supported.");
        return undef;
    }
    elsif ( $r->method() =~ /^DELETE$/i )
    {
        $r->log->error("DELETE request to the patch/\$pid interface. This is not supported.");
        return undef;
    }
    else
    {
        $r->log->error("Unknown request to the patch/\$pid interface.");
        return undef;
    }

    return undef;
}


#
# Apache Handler
# this is the main function of this request handler
#
sub handler {
    my $r = shift;
    $r->log->info("REST service request");
    my $path = sub_path($r);
    my $res = undef;

    # try to connect to the database - else report server error
    my $dbh = undef;
    if ( ! ($dbh=SMT::Utils::db_connect()) )
    {
        $r->log->error("RESTService could not connect to database.");
        return Apache2::Const::SERVER_ERROR;
    }

    # all REST Services need authentication
    return Apache2::Const::AUTH_REQUIRED unless ( defined $r->user  &&  $r->user ne '' );

    my ($status, $password) = $r->get_basic_auth_pw;
    return $status unless $status == Apache2::Const::OK;

    my $update_last_contact = update_last_contact($r, $dbh);
    if ( $update_last_contact )
    {
        $r->log->info(sprintf("Request from client (%s). Updated its last contact timestamp.", $r->user) );
    }
    else
    {
        $r->log->info(sprintf("Request from client (%s). Could not updated its last contact timestamp.", $r->user) );
    }

    my $JobsRequest         = qr{^jobs?};              # no trailing slash
    my $ClientsRequest      = qr{^clients?};           # no trailing slash
    my $ProductsRequest     = qr{^products?};          # products
    my $ReposRequest        = qr{^repos?};             # repos
    my $PatchesRequest      = qr{^patch(es)?};         # patches

    if    ( $path =~ $JobsRequest           ) {  $res = jobs_handler($r, $dbh);          }
    elsif ( $path =~ $ClientsRequest        ) {  $res = clients_handler($r, $dbh);       }
    elsif ( $path =~ $ProductsRequest       ) {  $res = products_handler($r, $dbh);      }
    elsif ( $path =~ $ReposRequest          ) {  $res = repos_handler($r, $dbh);         }
    elsif ( $path =~ $PatchesRequest        ) {  $res = patches_handler($r, $dbh);       }

    if (not defined $res)
    {
        # errors are logged in each handler
        # returning undef from a handler is allowed, this will result in a 404 response, just as if no handler was defined for the request
        return Apache2::Const::NOT_FOUND;
    }
    else
    {
        $r->content_type('text/xml');
        # $r->content_type('text/plain'); # could be enabled for testing
        $r->err_headers_out->add('Cache-Control' => "no-cache, public, must-revalidate");
        $r->err_headers_out->add('Pragma' => "no-cache");

        print $res;
    }

    # for testing only!! output some informative data about the request
    if (0) {
        my $writer = new XML::Writer(NEWLINES => 0);
        $writer->xmlDecl("UTF-8");

        $writer->startTag('testoutput');
        $writer->emptyTag('something',
                          'id'   =>  42,
                          'method'   => $r->method(),
                          'pathinfo' => $r->path_info(),
                          'unparsed_uri' => $r->unparsed_uri(),
                          'user'         => $r->user(),
                          'args'         => $r->args()
                     );
        $writer->startTag('resultdata');
        $writer->characters("$res");
        $writer->endTag('resultdata');
        $writer->endTag('testoutput');
        $writer->end();
    }

    # return a 200 response
    return Apache2::Const::OK;
}


#
# get the proper sub-path info part
#  cropps the prefix of the path: "/=/1/"
#
sub sub_path($)
{
    my $r = shift || return '';

    # get the path_info
    my $path = $r->path_info();
    # crop the prefix: '/=' rest service identifier, '/1' version number (currently there is only 1)
    $path =~ s/^\/(=\/)?1\///;
    # crop the trailing slash
    $path =~ s/\/?$//;

    return $path;
}

#
# update_last_contact
#
sub update_last_contact($$)
{
    my $r = shift || return undef;
    my $dbh = shift || return undef;

    my $client = SMT::Client->new({ 'dbh' => $dbh });
    return $client->updateLastContact($r->user);
}


1;

=head1 NAME

SMT::RESTService - REST service documentation

=head1 DESCRIPTION

To access the REST interface all URLs start with /=/1/ path.

=head1 Jobs Interface

=over 4

=item GET /jobs

Returns a list of all jobs

=item GET /jobs/@next

Return the next job

=item GET /jobs/<ID>

Return job information of the specified ID

=item PUT /jobs/<ID>

Finish job with the given ID

=back

=head1 Clients Interface

=over 4

=item GET /clients

Return a list of all clients

 <clients>
   <client id="1" description="" guid="bb75d9deb4724a0c937f018a45f2bf34"
           hostname="www" lastcontact="2010-04-15 17:18:03" namespace=""
           patchstatus_date="" patchstatus_o="" patchstatus_p=""
           patchstatus_r="" patchstatus_s="" target="sle-11-x86_64"/>
   <client id="1" .... />
 </clients>

=item GET /clients/<GUID>

Return client information of this GUID

   <client id="1" description="" guid="bb75d9deb4724a0c937f018a45f2bf34"
           hostname="www" lastcontact="2010-04-15 17:18:03" namespace=""
           patchstatus_date="" patchstatus_o="" patchstatus_p=""
           patchstatus_r="" patchstatus_s="" target="sle-11-x86_64"/>
   <client id="1" .... />

=item GET /clients/@all/jobs

Return a list of jobs of all clients

 <jobs>
   <job id="71" type="patchstatus" name="Patchstatus Job"
        description="Patchstatus Job for Client 4b4608ddc16e4b3fa1271df903056b3a"
        status="0" created="2011-07-25 12:19:42" upstream="0"
        cacheresult="0" verbose="0" timelag="23:00:00" persistent="1">
     <arguments/>
   </job>
   <job id="42" guid="123" type="patchstatus" name="Patchstatus Job"
        description="Patchstatus Job for Client 123" status="0" exitcode="0"
        created="2010-07-12 17:20:27" targeted="2012-02-03 11:36:02"
        retrieved="2012-02-02 12:36:01" finished="2012-02-02 12:36:02"
        upstream="0" cacheresult="0" verbose="0" timelag="23:00:00"
        message="0:0:0:0 # PackageManager=0 Security=0 Recommended=0
        Optional=0" persistent="1">
     <stdout>
       <![CDATA[ ]]>
     </stdout>
     <stderr>
       <![CDATA[ ]]>
     </stderr>
     <arguments/>
   </job>
   ...
 </jobs>

=item GET /clients/<GUID>/jobs

Return a list of jobs for the client specified by GUID

 <jobs>
   <job id="42" guid="123" type="patchstatus" name="Patchstatus Job"
        description="Patchstatus Job for Client 123" status="0" exitcode="0"
        created="2010-07-12 17:20:27" targeted="2012-02-03 11:36:02"
        retrieved="2012-02-02 12:36:01" finished="2012-02-02 12:36:02"
        upstream="0" cacheresult="0" verbose="0" timelag="23:00:00"
        message="0:0:0:0 # PackageManager=0 Security=0 Recommended=0
        Optional=0" persistent="1">
     <stdout>
       <![CDATA[ ]]>
     </stdout>
     <stderr>
       <![CDATA[ ]]>
     </stderr>
     <arguments/>
   </job>
   ...
 </jobs>

=item GET /clients/<GUID>/jobs/@next

Return the next job of the client specified by GUID.

=item GET /clients/<GUID>/jobs/<ID>

Return job information of a specific client and a specific job

=item GET /clients/@all/patchstatus

Return the patchstatus of all clients

 <clients>
   <client id="1" guid="f9c48ef7ae0c4ed39294f96715d36b50" patchstatus_date=""
           patchstatus_o="" patchstatus_p="" patchstatus_r="" patchstatus_s=""/>
   <client id=2" ... />
 </clients>

=item GET /clients/<GUID>/patchstatus

Return the patchstatus of the client specified by GUID

 <client id="1" guid="f9c48ef7ae0c4ed39294f96715d36b50" patchstatus_date=""
         patchstatus_o="" patchstatus_p="" patchstatus_r="" patchstatus_s=""/>

=back

=head1 Products Interface

=over 4

=item GET /products

Return a list of all products

 <products>
   <product name="SUSE_SLES" arch="x86_64" class="7261" id="3009" rel=""
            serverclass="OS" uiname="SUSE Linux Enterprise Server 11 SP2"
            version="11.2"/>
   <product name="SUSE_SLES" arch="i586" class="7261" id="3006" rel=""
            serverclass="OS" uiname="SUSE Linux Enterprise Server 11 SP2"
            version="11.2"/>
   ...
 </products>

=item GET /products/<ID>

Return the product specified by ID

 <product name="SUSE_SLES" arch="x86_64" class="7261" id="3009" rel=""
          serverclass="OS" uiname="SUSE Linux Enterprise Server 11 SP2"
          version="11.2"/>

=item GET /products/<ID>/repos

Return repositories of a specific product id

 <repos>
   <repo name="SLES11-SP1-Updates" id="1094" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-WebYaST-SP2-Pool" id="1218" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP1-Debuginfo-Pool" id="1396" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLE11-WebYaST-SP2-Updates" id="984" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Core" id="1032" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-Extras" id="998" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP1-Pool" id="1053" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP2-Debuginfo-Updates" id="1269" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Extension-Store" id="1401" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Updates" id="1296" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP1-Debuginfo-Updates" id="845" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP2-Debuginfo-Core" id="934" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
 </repos>

=back

=head1 Repository Interface

=over 4

=item GET /repos

Return a list of all repositories

 <repos>
   <repo name="SLES11-SP1-Updates" id="1094" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-WebYaST-SP2-Pool" id="1218" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP1-Debuginfo-Pool" id="1396" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLE11-WebYaST-SP2-Updates" id="984" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Core" id="1032" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-Extras" id="998" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP1-Pool" id="1053" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP2-Debuginfo-Updates" id="1269" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Extension-Store" id="1401" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLES11-SP2-Updates" id="1296" mirrored="" optional="N"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP1-Debuginfo-Updates" id="845" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   <repo name="SLE11-SP2-Debuginfo-Core" id="934" mirrored="" optional="Y"
         target="sle-11-x86_64"/>
   ...
 </repos>


=item GET /repos/<ID>

Return the repository specified by ID

 <repo name="SLE11-SP2-Debuginfo-Core" id="934" target="sle-11-x86_64"
       type="nu">
   <description>SLE11-SP2-Debuginfo-Core for sle-11-x86_64</description>
   <localpath>
     /space/mirror/repo/$RCE/SLE11-SP2-Debuginfo-Core/sle-11-x86_64
   </localpath>
   <mirrored date=""/>
   <url>
     https://nu.novell.com/repo/$RCE/SLE11-SP2-Debuginfo-Core/sle-11-x86_64/
   </url>
 </repo>

=item GET /repos/<ID>/patches

Return a list of patches in the repository specified with ID

 <patches>
   <patch name="slessp1-sle-apparmor-quick_en-pdf" category="recommended"
          id="4591" version="3885"/>
   <patch name="slessp1-apache2-mod_php5" category="recommended"
          id="4842" version="3264"/>
   <patch name="slessp1-at" category="recommended" id="4513"
          version="4571"/>
   ...
 </patches>

=back

=head1 Patches Interface

=over 4

=item GET /patches/<ID>

Return information about a specific patch defined by ID

 <patch name="slessp1-sle-apparmor-quick_en-pdf" category="recommended" id="4591" version="3885">
   <description>
     This update provides the latest corrections and addtions to the SLES Manuals. In addition, it provides a new chapter about KVM.
   </description>
   <issued date="1296214440"/>
   <packages>
     <package name="sles-admin_en-pdf" arch="noarch" epoch="" release="16.25.1" version="11.1">
       <origlocation>
         https://nu.novell.com/repo/$RCE/SLES11-SP1-Updates/sle-11-x86_64/rpm/noarch/sles-admin_en-pdf-11.1-16.25.1.noarch.rpm
       </origlocation>
       <smtlocation>
         https://smt.example.com/repo/$RCE/SLES11-SP1-Updates/sle-11-x86_64/rpm/noarch/sles-admin_en-pdf-11.1-16.25.1.noarch.rpm
       </smtlocation>
     </package>
     <package>
     ...
   </package>
   <references>
     <reference id="664232" href="https://bugzilla.novell.com/show_bug.cgi?id=664232" title="bug number 664232" type="bugzilla"/>
   </references>
   <title>
     Recommended update for SLES Manual Update and KVM User Guide
   </title>
 </patch>

=back

=head1 AUTHOR

mc@suse.de, jdsn@suse.de

=head1 COPYRIGHT

Copyright 2012 SUSE LINUX Products GmbH, Nuernberg, Germany.

=cut
