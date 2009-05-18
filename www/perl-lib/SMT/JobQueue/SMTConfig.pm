#!/usr/bin/env perl

package SMTConfig;
use SMTUtils;
use Config::IniFiles;


use strict;
use warnings;



my $smtUrl = undef;

sub smtUrl
{
  if (! defined ( $smtUrl ))
  {
    $smtUrl = readSmtUrl();
  }
    
  return $smtUrl;
}


sub readSmtUrl
{
  my $uri;
  open(FH, "< /etc/suseRegister.conf") or error ("Cannot open /etc/suseRegister.conf");
  while(<FH>)
  {
    if($_ =~ /^url\s*=\s*(\S*)\s*/ && defined $1 && $1 ne "")
    {
      $uri = $1;
      last;
    }
  }
  close FH;
  if(!defined $uri || $uri eq "")
  {
    SMTUtils::error("Cannot read URL from /etc/suseRegister.conf");
  }
  return $uri;
}


sub getSMTClientConfig
{
  my $section = shift;
  my $key = shift;

  my $cfg = new Config::IniFiles( -file => SMTConstants::CLIENT_CONFIG_FILE );
  if(!defined $cfg)
  {
    SMTUtils::error("Cannot read the SMT client configuration file");
  }

  return $cfg->val($section, $key);
}



1;
