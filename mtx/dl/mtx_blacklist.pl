#!/usr/bin/perl

# (c) Darxus@ChaosReigns.com, released under the GPL.
# Update MTX blacklist.
# http://www.chaosreigns.com/mtx/
#
# 2010-02-14 Initial release.

use warnings;
use strict;
use LWP::Simple;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

my %score;
   $score{'somespam'} = 4;
   $score{'allspam'} = $score{'somespam'} + 100;
my $gzfile = "/etc/spamassassin/mtx_blacklist.gz";
my $safile = "/etc/spamassassin/mtx_blacklist.cf";
my $url = "http://www.mtxbl.chaosreigns.com/mtxbl.gz";

my %typename = (
    1, 'somespam',
    2, 'allspam',
);

$url = $ARGV[0] if ( defined $ARGV[0] );

my $rc = mirror($url, $gzfile);
if (is_error($rc)) {
  die("Download failed.");
}
unless ($rc == RC_NOT_MODIFIED) {
  my $z = new IO::Uncompress::Gunzip $gzfile or die "gunzip failed: $GunzipError";
  open OUT, ">$safile" or die "Couldn't write to $safile: $!";
  while (my $line = $z->getline()) {
    chomp $line;
    if ($line =~ /(1|2) (\S+)\s*(?:$|#)/) {
      my $type = $1;
      my $domain = $2;
      print OUT "mtx_blacklist *.$domain $score{$typename{$type}}\n";
    }
  }
  close OUT;
}

exit; ###############################################
