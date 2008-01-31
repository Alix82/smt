package YEP::CLI;
use strict;
use warnings;

=head1 NAME

 YEP::CLI - YEP common actions for command line programs

=head1 SYNOPSIS

  YEP::listProducts();
  YEP::listCatalogs();
  YEP::setupCustomCatalogs();

=head1 DESCRIPTION

Common actions used in command line utilities that administer the
YEP system.

=head1 METHODS

=over 4

=item listProducts

Shows products. Pass mirrorable => 1 to get only mirrorable
products. 0 for non-mirrorable products, or nothing to get all
products.

=item listRegistrations

Shows active registrations on the system.


=item setupCustomCatalogs

modify the database to setup catalogs create by the customer

=item setCatalogDoMirror

set the catalog mirror flag to enabled or disabled

Pass id => foo to select the catalog.
Pass enabled => 1 or enabled => 0
disabled => 1 or disabled => 0 are supported as well

=item catalogDoMirrorFlag

Pass id => foo to select the catalog.
true if the catalog is ser to be mirrored, false otherwise

=back

=back

=head1 AUTHOR

dmacvicar@suse.de

=head1 COPYRIGHT

Copyright 2007, 2008 SUSE LINUX Products GmbH, Nuernberg, Germany.

=cut


use URI;
use YEP::Utils;
use Config::IniFiles;
use File::Temp;
use IO::File;
use YEP::Parser::NU;
use YEP::Mirror::Job;
use XML::Writer;

use Locale::gettext ();
use POSIX ();     # Needed for setlocale()

POSIX::setlocale(&POSIX::LC_MESSAGES, "");

#use vars qw($cfg $dbh $nuri);

#print "hello CLI2\n";


sub init
{
    my $dbh;
    my $cfg;
    my $nuri;
    if ( not $dbh=YEP::Utils::db_connect() )
    {
        die __("ERROR: Could not connect to the database");
    }

    #print "hello CLI\n";
    $cfg = new Config::IniFiles( -file => "/etc/yep.conf" );
    if(!defined $cfg)
    {
        die __("Cannot read the YEP configuration file: ").@Config::IniFiles::errors;
    }

    # TODO move the url assembling code out
    my $NUUrl = $cfg->val("NU", "NUUrl");
    if(!defined $NUUrl || $NUUrl eq "")
    {
      die __("Cannot read NU Url");
    }

    my $nuUser = $cfg->val("NU", "NUUser");
    my $nuPass = $cfg->val("NU", "NUPass");
    
    if(!defined $nuUser || $nuUser eq "" ||
      !defined $nuPass || $nuPass eq "")
    {
        die __("Cannot read the Mirror Credentials");
    }

    $nuri = URI->new($NUUrl);
    $nuri->userinfo("$nuUser:$nuPass");

    return ($cfg, $dbh, $nuri);
}

sub listCatalogs
{
    my %options = @_;

    my ($cfg, $dbh, $nuri) = init();
    my $sql = "select * from Catalogs";

    $sql = $sql . " where 1";

    if ( exists $options{ mirrorable } && defined $options{mirrorable} )
    {
          if (  $options{ mirrorable } == 1 )
          {
            $sql = $sql . " and MIRRORABLE='Y'";
          }
          else
          {
            $sql = $sql . " and MIRRORABLE='N'";
          }
    }

    if ( exists $options{ name } && defined $options{name} )
    {
          $sql = $sql . sprintf(" and NAME=%s", $dbh->quote($options{name}));
    }
    
    if ( exists $options{ domirror } && defined  $options{ domirror } )
    {
          if (  $options{ domirror } == 1 )
          {
            $sql = $sql . " and DOMIRROR='Y'";
          }
          else
          {
            $sql = $sql . " and DOMIRROR='N'";
          }
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my @values = $sth->fetchrow_array())  
    {
        print $values[0] . " => [" . $values[1] . "] " . $values[2] . "\n";
        if ( exists $options{ verbose } && defined $options{verbose} )
        {
          print "|\\-local-path => " . $values[4] . "\n";
          print "| -url        => " . $values[5] . "\n";
          print "| -type       => " . $values[6] . "\n";
          print "| -mirrorable => " . $values[8] . "\n";
          print "| -mirror?    => " . $values[7] . "\n";
        }
    }
    $sth->finish();
}

sub listProducts
{
    my %options = @_;
    my ($cfg, $dbh, $nuri) = init();

    my $sth = $dbh->prepare(qq{select * from Products});
    $sth->execute();
    while (my ( $PRODUCTDATAD,
                $PRODUCT,
                $VERSION,
                $REL,
                $ARCH,
                $PRODUCTLOWER,
                $VERSIONLOWER,
                $RELLOWER,
                $ARCHLOWER,
                $FRIENDLY,
                $PARAMLIST,
                $NEEDINFO,
                $SERVICE,
                $PRODUCT_LIST ) =
                $sth->fetchrow_array())  # keep fetching until 
                                         # there's nothing left
    {
        #print "$nickname, $favorite_number\n";
	#print "$PRODUCT $VERSION $ARCH\n";
	my $productstr = $PRODUCT;
	$productstr .= " $VERSION" if(defined $VERSION);
	$productstr .= " $ARCH" if(defined $ARCH);
	print "$productstr\n";
        if ( exists $options{ verbose } && defined $options{verbose} )
        {
          #print "$PARAMLIST\n";
        }
    }
    $sth->finish();
}

sub listRegistrations
{
    my ($cfg, $dbh, $nuri) = init();

    my $sth = $dbh->prepare(qq{select r.GUID,p.PRODUCT from Registration r, Products p where r.PRODUCTID=p.PRODUCTDATAID});
    $sth->execute();
     while (my @values =
                 $sth->fetchrow_array())  # keep fetching until 
                                          # there's nothing left
    {
        #print "$nickname, $favorite_number\n";
        print "[" . $values[0] . "]" . " => " . $values[1] . "\n";
    }
    $sth->finish();
}

sub resetCatalogsStatus
{
  my ($cfg, $dbh, $nuri) = init();

  my $sth = $dbh->prepare(qq{UPDATE Catalogs SET Mirrorable='N' WHERE CATALOGTYPE='nu'});
  $sth->execute();
}

sub setCatalogDoMirror
{
  my %opt = @_;
  my ($cfg, $dbh, $nuri) = init();

  if(exists $opt{enabled} && defined $opt{enabled} )
  {
    my $sql = "update Catalogs";
    $sql .= sprintf(" set Domirror=%s", $dbh->quote(  $opt{enabled} ? "Y" : "N" ) ); 

    $sql .= " where 1";

    $sql .= sprintf(" and Mirrorable=%s", $dbh->quote("Y"));

    if(exists $opt{name} && defined $opt{name} )
    {
      $sql .= sprintf(" and NAME=%s", $dbh->quote($opt{name}));
    }

    if(exists $opt{target} && defined $opt{target} )
    {
      $sql .= sprintf(" and TARGET=%s", $dbh->quote($opt{target}));
    }

    if(exists $opt{id} && defined $opt{id} )
    {
      $sql .= sprintf(" and CATALOGID=%s", $dbh->quote($opt{id}));
    }

    #print $sql . "\n";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

  }
  else
  {
    die __("enabled option missing");
  }
}

sub catalogDoMirrorFlag
{
  my %options = @_;
  my ($cfg, $dbh, $nuri) = init();
  return 1;
}

sub setMirrorableCatalogs
{
    my %opt = @_;
    my ($cfg, $dbh, $nuri) = init();

    # create a tmpdir to store repoindex.xml
    my $destdir = File::Temp::tempdir(CLEANUP => 1);
    my $indexfile = "";
    if(exists $opt{todir} && defined $opt{todir} && -d $opt{todir})
    {
        $destdir = $opt{todir};
    }

    if(exists $opt{fromdir} && defined $opt{fromdir} && -d $opt{fromdir})
    {
        $indexfile = $opt{fromdir}."/repo/repoindex.xml";
    }
    else
    {
        # get the file
        my $job = YEP::Mirror::Job->new();
        $job->uri($nuri);
        $job->localdir($destdir);
        $job->resource("/repo/repoindex.xml");
    
        $job->mirror();
	$indexfile = $job->local();
    }

    if(exists $opt{todir} && defined $opt{todir} && -d $opt{todir})
    {
        # with todir we only want to mirror repoindex to todir
        return;
    }

    my $parser = YEP::Parser::NU->new();
    $parser->parse($indexfile, sub {
                                    my $repodata = shift;
                                    print __(sprintf("* set [" . $repodata->{NAME} . "] [" . $repodata->{DISTRO_TARGET} . "] as mirrorable.\n"));
                                    my $sth = $dbh->do( sprintf("UPDATE Catalogs SET Mirrorable='Y' WHERE NAME=%s AND TARGET=%s", $dbh->quote($repodata->{NAME}), $dbh->quote($repodata->{DISTRO_TARGET}) ));
                               }
    );

    my $sql = "select CATALOGID, NAME, LOCALPATH, EXTURL, TARGET from Catalogs where CATALOGTYPE='yum'";
    #my $sth = $dbh->prepare($sql);
    #$sth->execute();
    #while (my @values = $sth->fetchrow_array())
    my $values = $dbh->selectall_arrayref($sql);
    foreach my $v (@{$values})
    { 
        my $catName = $v->[1];
        my $catLocal = $v->[2];
        my $catUrl = $v->[3];
        my $catTarget = $v->[4];
        if( $catUrl ne "" && $catLocal ne "" )
        {
	    my $ret = 1;
            if(exists $opt{fromdir} && defined $opt{fromdir} && -d $opt{fromdir})
            {
		    # fromdir is used on a server without internet connection
		    # we define that the catalogs are mirrorable
		    $ret = 0;
	    }
	    else
	    {
    	        my $tempdir = File::Temp::tempdir(CLEANUP => 1);
                my $job = YEP::Mirror::Job->new();
                $job->uri($catUrl);
                $job->localdir($tempdir);
                $job->resource("/repodata/repomd.xml");
          
                # if no error
                $ret = $job->mirror();
	    }
            print __(sprintf ("* set [" . $catName . "] as " . ( ($ret == 0) ? '' : ' not ' ) . " mirrorable.\n"));
            my $sth = $dbh->do( sprintf("UPDATE Catalogs SET Mirrorable=%s WHERE NAME=%s AND TARGET=%s", ( ($ret == 0) ? $dbh->quote('Y') : $dbh->quote('N') ), $dbh->quote($catName), $dbh->quote($catTarget) ) );
        }
    }

}

sub removeCustomCatalog
{
    my %options = @_;
    my ($cfg, $dbh, $nuri) = init();

    # delete existing catalogs with this id

    my $affected1 = $dbh->do(sprintf("DELETE from Catalogs where CATALOGID=%s", $dbh->quote($options{catalogid})));
    my $affected2 = $dbh->do(sprintf("DELETE from ProductCatalogs where CATALOGID=%s", $dbh->quote($options{catalogid})));

    return ($affected1 || $affected2);
}

sub setupCustomCatalogs
{
    my %options = @_;
    my ($cfg, $dbh, $nuri) = init();

    # delete existing catalogs with this id
    
    removeCustomCatalog(%options);
    
    # now insert it again.
    my $affected = $dbh->do(sprintf("INSERT INTO Catalogs VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                                     $dbh->quote($options{catalogid}),
                                     $dbh->quote($options{name}),
                                     $dbh->quote($options{description}),
                                     "NULL",
                                     $dbh->quote("/RPMMD/".$options{name}),
                                     $dbh->quote($options{exturl}),
                                     $dbh->quote("yum"),
                                     $dbh->quote("Y"),
                                     $dbh->quote("Y")));
    foreach my $pid (@{$options{productids}})
    {
        $affected += $dbh->do(sprintf("INSERT INTO ProductCatalogs VALUES(%s, %s, %s)",
                                      $pid,
                                      $dbh->quote($options{catalogid}),
                                      $dbh->quote("N")));
    }
    
    return (($affected>0)?1:0);
}

sub createDBReplacementFile
{
    my $xmlfile = shift;
    my ($cfg, $dbh, $nuri) = init();

    my $dbout = $dbh->selectall_hashref("SELECT CATALOGID, NAME, DESCRIPTION, TARGET, EXTURL, LOCALPATH, CATALOGTYPE from Catalogs where DOMIRROR = 'Y'", 
                                        "CATALOGID");

    my $output = new IO::File(">$xmlfile");
    my $writer = new XML::Writer(OUTPUT => $output);

    $writer->xmlDecl("UTF-8");
    $writer->startTag("catalogs", xmlns => "http://www.novell.com/xml/center/regsvc-1_0");

    foreach my $row (keys %{$dbout})
    {
        $writer->startTag("row");
	foreach my $col (keys %{$dbout->{$row}})
	{
            $writer->startTag("col", name => $col);
	    $writer->characters($dbout->{$row}->{$col});
	    $writer->endTag("col");
	}
	$writer->endTag("row");
    }
    $writer->endTag("catalogs");
    $writer->end();
    $output->close();

    return ;
}
1;
