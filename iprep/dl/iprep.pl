#!/usr/bin/perl
#
# iprep.pl, (c) 2011 Darxus@ChaosReigns.com, 
#   released under the Apache License, Version 2.0 or newer.
#
# Reports sending IP address and date of hams and spams for use in a reputation system.
#
# Dependencies: SpamAssassin needs to be installed for use of some of its modules.
#
# Usage:
# ./iprep.pl ham:dir:~/masscheckwork/ham spam:dir:~/masscheckwork/spam/
#
# The arguments are the same "targets" used by SpamAssassin's mass-check:
#    <class>:<format>:<location>
#    <class>       is "spam" or "ham"
#    <format>      is "dir", "file", "mbx", "mbox", or "detect"
#    <location>    is a file or directory name.  globbing of ~ and * is supported
#
# You can specify many targets at once.
#
# Additional optional commandline argument --logname=<name> allows you
# to customize the output log file names.
#
# Config file ~/.ipreprc:
# $trusted_networks = '<space delimited list of trusted hosts>';
# $user = 'username';
# $pass = 'password';
#
# Include everything from both trusted_networks and internal_networks
# from your SpamAssassin configuration.  Documentation of them is here:
# http://spamassassin.apache.org/full/3.3.x/doc/Mail_SpamAssassin_Conf.html#network_test_options
# http://wiki.apache.org/spamassassin/TrustPath
#
# Outputs files to $workdir/iprep-$class-$user$logname.log and rsyncs
# them to $user@chaosreigns.com::$user
#
# The arguments --live-ham and --live-spam allow you to feed it one
# email of the specified type on stdin.  Output is uploaded with the
# --upload argument (probably in cron).
# Usage:
# cat email.txt | ./iprep.pl --live-ham
# ./iprep.pl --upload
#
# Output sample: 
# $ head iprep-spam-darxus.log
# 1298981048 77.55.116.13
# 1299202198 208.89.10.45
# 1299245987 120.138.17.204
# 1299246951 120.138.17.204
# 1299792485 208.109.80.73
#
# ChangeLog
# 2011-03-29 1 Initial release.
# 2011-03-31 1 Added --live-ham / --live-spam.
# 2011-03-31 2 Added --upload, --live-* nolonger uploads.
# 2011-04-07 1 Quiet mode via -q argument.  Handle parse_received_line()
#              returning undef, reported by Andreas Schulze.

use strict;
use warnings;
use NetAddr::IP;
use Mail::SpamAssassin::Message::Metadata::Received qw(parse_received_line);
use Date::Parse; # str2time
use Mail::SpamAssassin::ArchiveIterator;

# Parse config file ~/.ipreprc
my $workdir = "$ENV{HOME}/iprep";
my $debug = 0;
my $user = ''; 
my $pass = ''; 
my $trusted_networks = '';
my $logname = '';
my $server = 'iprepr.chaosreigns.com';
open CONF, "<$ENV{HOME}/.ipreprc" or die "Couldn't read config file ~/.iperprc: $!";
while (my $line = <CONF>) {
  chomp $line;
  if ($line =~ m#user.*=.*['"](.+)['"].*;#) {
    $user = $1; 
  } elsif ($line =~ m#pass.*=.*['"](.+)['"].*;#) {
    $pass = $1; 
  } elsif ($line =~ m#trusted_networks.*=.*['"](.+)['"].*;#) {
    $trusted_networks = $1; 
  } elsif ($line =~ m#workdir.*=.*['"](.+)['"].*;#) {
    $workdir = $1; 
  } elsif ($line =~ m#debug.*=.*['"](.+)['"].*;#) {
    $debug = $1; 
  } elsif ($line =~ m#server.*=.*['"](.+)['"].*;#) {
    $server = $1; 
  }
}
close CONF;

my $live = 0;
my $upload = 0;
my $class = '';
my $quiet = 0;
# Parse arguments.
my @args = ();
for my $arg (@ARGV) {
  if ($arg =~ m#^--logname=(.*)$#) { ##
    $logname = "-$1";
  } elsif ($arg eq '--live-ham') {
    $live = 1;
    $class = 'h';
  } elsif ($arg eq '--live-spam') {
    $live = 1;
    $class = 's';
  } elsif ($arg eq '--upload') {
    $upload = 1;
  } elsif ($arg eq '-q') {
    $quiet = 1;
  } else {
    push @args, $arg;
  }
}

unless (-d $workdir) {
  mkdir $workdir or die "Couldn't create $workdir: $!";
}

my @trusted_net = ();
for my $ip (split ' ', $trusted_networks) {
  push @trusted_net, NetAddr::IP->new($ip);
}

our $hamcount = 0;
our $spamcount = 0;

if ($upload) {
  if (-e "$workdir/iprep-ham-live-new-$user$logname.log" and -e "$workdir/iprep-spam-live-new-$user$logname.log") {
    my $time = time;
    rename "$workdir/iprep-ham-live-new-$user$logname.log", "$workdir/iprep-ham-live-$time-$user$logname.log";
    rename "$workdir/iprep-spam-live-new-$user$logname.log", "$workdir/iprep-spam-live-$time-$user$logname.log";
  
    print "Uploading.\n" unless ($quiet);
    &upload("$workdir/iprep-ham-live-$time-$user$logname.log $workdir/iprep-spam-live-$time-$user$logname.log");
    open OUT, ">$workdir/last_uploaded.txt" or die "Couldn't write to $workdir/last_uploaded.txt: $!";
    print OUT "$time\n";
    close OUT;
  } else {
    print "Nothing new to upload.\n" unless ($quiet);
  }
} elsif ($live) {
  open HAMLOG, ">>$workdir/iprep-ham-live-new-$user$logname.log" or die "Couldn't write to ham log: $!";
  open SPAMLOG, ">>$workdir/iprep-spam-live-new-$user$logname.log" or die "Couldn't write to spam log: $!";
  our @input = <STDIN>;
  &parsefile($class,'stdin', undef, \@input);
  print "$hamcount ham, $spamcount spam.\n" unless ($quiet);
  close HAMLOG;
  close SPAMLOG;
} else {
  open HAMLOG, ">$workdir/iprep-ham-$user$logname.log" or die "Couldn't write to ham log: $!";
  open SPAMLOG, ">$workdir/iprep-spam-$user$logname.log" or die "Couldn't write to spam log: $!";
  my $iter = new Mail::SpamAssassin::ArchiveIterator(
    {   
      'opt_all'   => 1,
      'opt_skip_empty_messages' => 1,
      'opt_want_date' => 0, # Doesn't work with --live :(
    }
  );
  
  $iter->set_functions( \&parsefile, sub { } );
  
  eval { $iter->run(@args); };
  close HAMLOG;
  close SPAMLOG;

  print "$hamcount ham, $spamcount spam.  Uploading.\n" unless ($quiet);
  &upload("$workdir/iprep-ham-$user$logname.log $workdir/iprep-spam-$user$logname.log");
}


exit ; #######################################################################

sub upload {
  my $files = shift;
  $ENV{RSYNC_PASSWORD} = $pass;
  if ($quiet) {
    system("rsync -qaz $files $user\@${server}::$user");
  } else {
    system("rsync -vaz $files $user\@${server}::$user");
  }
  $ENV{RSYNC_PASSWORD} = '';
}

sub parsefile {
  my($class, $filename, undef, $msg_array) = @_;
  #print "class: $class filename: $filename date: $recv_date\n";

  # Find Received: headers and unfold them.
  my @lines = ();
  my $received = '';
  for my $line (@$msg_array) {
    chomp $line;
    #print "line:$line:\n";
    if ($line =~ m#^$#) { ##
      # End of headers.
      push @lines, $received unless ($received eq '');
      print "- End of headers: $received\n" if $debug;
      $received = '';
      last;
    } elsif ($line =~ m#^Received: (.*)$#) { ##
      my $newreceived = $1;
      push @lines, $received unless ($received eq '');
      $received = $newreceived;
      print "- Begin received header: $received\n" if $debug;
    } elsif ($line =~ m#\t(.*)$#) { ##
      $received .= ' ' . $1 unless ($received eq '');
      print "- Continue received header: $received\n" if ($debug and not $received eq '');
    } else {
      push @lines, $received unless ($received eq '');
      $received = '';
    }
  }
  
  my $recv_date = 0;
  # Look through IPs in Received headers until I find one that's not trusted.
  my $lastrelay = 'none';
  my $lastuntrusted = 'none';
  my $self = new(); # Dummy to satisfy SA function
  for my $line (@lines) {
    print "line:$line:\n" if $debug;
    if (not $recv_date and $line =~ m#;([^;]+)$#) { ##
      $recv_date = str2time($1);
      unless (defined $recv_date) {
        print "Couldn't parse date: $line\n";
      }
    }
    my $istrusted = 0;
    my $relay = Mail::SpamAssassin::Message::Metadata::parse_received_line($self,$line);
    if (!defined $relay or $relay == 0) {
  #    print "Header got skipped.\n";
      next;
    }
    my %relay = %$relay;
    print "\nIP: $relay{ip}\n" if $debug;
    $lastrelay = $relay{ip};
  
#    for my $key (keys %relay) {
#      print "$key $relay{$key}\n";
#    }
  
    if ($relay{ip_private}) {
      $istrusted = 1; 
      print "Private IP.\n" if $debug;
    } elsif ($trusted_networks) {
      my $relay_obj = NetAddr::IP->new($relay{ip});
      for my $trusted (@trusted_net) {
        if ($trusted->contains($relay_obj)) {
          $istrusted = 1;
          print "Trusted.\n" if $debug;
        }
      }
    } elsif ($relay{auth}) {
      # $trusted_networks isn't defined, do some inferring of trust
      $istrusted = 1; 
      print "Trust inferred.\n" if $debug;
    }
    unless ($istrusted) {
      print "Untrusted.\n" if $debug;
      $lastuntrusted = $lastrelay;
      last;
    }
  }
  
  #print "\nLast untrusted relay: $lastuntrusted\n";
  if ($class eq 'h') {
    print HAMLOG "$recv_date $lastuntrusted\n" unless ($lastuntrusted eq 'none');
    $hamcount++;
  } elsif ($class eq 's') {
    print SPAMLOG "$recv_date $lastuntrusted\n" unless ($lastuntrusted eq 'none');
    $spamcount++;
  }
}


# Empty to satisfy stuff Mail::SpamAssassin::Message::Metadata::parse_received_line does with $self.
sub new {
  my $self = {};
  bless $self;
  # Why does this work without "return $self" here?
}
sub make_relay_as_string {
}
