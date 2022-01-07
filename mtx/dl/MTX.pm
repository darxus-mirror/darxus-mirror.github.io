
# MTX plugin for SpamAssassin
# (c) Darxus@ChaosReigns.com, released under the GPL.
# http://www.chaosreigns.com/mtx/
#
# 2010-02-10    Initial release.
# 2010-02-12    Implemented blacklisting, switched to SA's DnsResolver
# 2010-02-12-01 Fixed failure to handle IP CNAME caused in previous.
#               Reduce chances of exploiting flaws by more defaulting to
#               "fail".
# 2010-02-12-01 Switched from last external to last untrusted relay.
# 2010-02-13    Rename of above.
# 2010-02-13-01 Don't "fail" on "last untrusted relay unavailable".
# 2010-02-14    Rename of above.
# 2010-02-14-01 Implemented policy record without delegation.
# 2010-02-14-02 Implemented policy record delegation.
# 2010-02-14-03 Fixed whining about "implicit split to @_".
# 2010-02-15    Rename of above.
# 2010-02-15-01 Don't check Policy of None has already been determined.
# 2010-02-15-02 Removed unnecessary variable $arraydepth.
# 2010-02-15-03 Minor tidying.
# 2010-02-15-04 Removed unnecessary variable $hostname.
# 2010-02-15-05 Further minor tidying.
# 2010-02-16    Rename of above.
# 2010-02-15-01 Switched back to Net::DNS::Resolver for SpamAssassin v3.3.0 compatability.
#               All releases pass harness testing on SA v3.2.5 + perl
#               v5.8.8 and v3.3.0 + perl v5.10.0 starting here.
# 2010-10-19    Throw a freaking error if the DNS lookup fails.  Thanks to
#               Patrick Domack for reporting.
# 2010-10-24    If DNS lookup on sending IP returns something but it
#               contains nothing, also set mtx_none so check_polciy
#               doesn't get run.  Thanks to Patrick Domack for reporting.
# 2011-05-29    IPv6 support by Andreas Schulze.
# 2019-03-02    Spamassassin renamed
#               Mail::SpamAssassin::Util::RegistrarBoundaries to 
#               Mail::SpamAssassin::RegistryBoundaries 
#
# TODO
# * Switch to Mail::SpamAssassin::DnsResolver::bgsend ?

=head1 NAME

MTX - MTX

=head1 SYNOPSIS

# http://www.chaosreigns.com/mtx/

loadplugin Mail::SpamAssassin::Plugin::MTX

header   MTX_PASS eval:check_mtx_pass()
score    MTX_PASS -5
describe MTX_PASS MTX: Passed: http://www.chaosreigns.com/mtx/

header   MTX_FAIL eval:check_mtx_fail()
score    MTX_FAIL 1
describe MTX_FAIL MTX: Failed: http://www.chaosreigns.com/mtx/

header   MTX_BLACKLIST eval:check_mtx_blacklist()
# Do not define a score, it's defined with mtx_blacklist.
describe MTX_BLACKLIST MTX: On your blacklist.

# Blacklist by the host name (PTR) of the sending IP (last untrusted relay).
# Second argument is the score to assign, use whatever you want.
mtx_blacklist *.example.com  5   # Known to send spam *and* nonspam, nullify PASS score.
mtx_blacklist *.example2.com 100 # Only sends spam, big penalty.

=head1 DESCRIPTION

Write the above lines in the synopsis to
C</etc/spamassassin/local.cf>.

=cut

use strict;
use warnings;

package Mail::SpamAssassin::Plugin::MTX;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger; # dbg()
# REVIEW: does including Net::IP introduce performance
#         or massiv memory usage changes?
# REVIEW: may this trigger problems outside this plugin?
use Net::IP;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);
#my $res = Mail::SpamAssassin::DnsResolver->new;
my $res = Net::DNS::Resolver->new;

sub new {
  my $class = shift;
  my $mailsaobject = shift;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  $self->register_eval_rule ("check_mtx_pass");
  $self->register_eval_rule ("check_mtx_fail");
  $self->register_eval_rule ("check_mtx_none");
  $self->register_eval_rule ("check_mtx_neutral");
  $self->register_eval_rule ("check_mtx_softfail");
  $self->register_eval_rule ("check_mtx_hardfail");
  $self->register_eval_rule ("check_mtx_blacklist");

  $self->set_config($mailsaobject->{conf});

  return $self;
}

sub check_mtx_pass {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return $scanner->{mtx_pass};
}
sub check_mtx_fail {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return $scanner->{mtx_fail};
}
sub check_mtx_none {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return 0 if ( $scanner->{mtx_hardfail} );
  &check_policy if ( $scanner->{mtx_fail} and ! $scanner->{policy_checked} 
                     and ! $scanner->{mtx_none} );
  return $scanner->{mtx_none};
}
sub check_mtx_neutral {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return 0 if ( $scanner->{mtx_hardfail} );
  &check_policy if ( $scanner->{mtx_fail} and ! $scanner->{policy_checked} 
                     and ! $scanner->{mtx_none} );
  return $scanner->{mtx_neutral};
}
sub check_mtx_softfail {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return 0 if ( $scanner->{mtx_hardfail} );
  &check_policy if ( $scanner->{mtx_fail} and ! $scanner->{policy_checked} 
                     and ! $scanner->{mtx_none} );
  return $scanner->{mtx_softfail};
}
sub check_mtx_hardfail {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  return 1 if ( $scanner->{mtx_hardfail} );
  &check_policy if ( $scanner->{mtx_fail} and ! $scanner->{policy_checked} 
                     and ! $scanner->{mtx_none} );
  return $scanner->{mtx_hardfail};
}

sub check_policy {
  my ($self,$scanner) = @_;
  $scanner->{policy_checked} = 1;
  my $participant = 0;
  dbg("mtx: Checking MTX Policy.");
  #use Mail::SpamAssassin::Util::RegistrarBoundaries;
  use Mail::SpamAssassin::RegistryBoundaries;
  my $domain =  Mail::SpamAssassin::Util::RegistrarBoundaries::trim_domain($scanner->{hostname});
  my @hostname = split('\.', $scanner->{hostname});
  my $policy_mindepth = scalar( @{[split('\.', $domain)]} );
  my $policy_maxdepth = scalar( @hostname );
  $policy_maxdepth = 20 if ($policy_maxdepth > 20);
  dbg ("mtx: Policy mindepth: $policy_mindepth, maxdepth: $policy_maxdepth" );
  for my $policy_depth ($policy_mindepth .. $policy_maxdepth) {
    my $delegate = 0;
    my $policyfound = 0;
    $domain = join('.',reverse((reverse(@hostname))[0 .. $policy_depth -1]));
    my $policy = "policy.mtx.$domain";
    dbg("mtx: MTX Policy record name: $policy, depth: $policy_depth");
    my $packet = $res->send($policy, 'A');
    unless (defined $packet) {
      dbg('mtx: DNS "A" record lookup failed.  You appear to have a DNS problem:  ', $res->errorstring);
      return;
    }
    my @answer = $packet->answer;
    unless (@answer) {
      dbg("mtx: Failed to get policy record $policy.");
      $scanner->{mtx_none}=1;
      return;
    }
    for my $rr (@answer) {
      if (${$rr}{type} eq 'A') {
        my $address = ${$rr}{address};
        unless (defined $address) {
          dbg("mtx: A record exists but has no value.  I don't think this is possible.");
          $scanner->{mtx_none}=1;
          return;
        }
        dbg("mtx: MTX Policy record value: $address.");
        if ($address =~ m#^127\.\d{1,3}\.(0|1)\.(0|1|2)$#) { ##
          $delegate = $1;
          $participant = $2;
          $policyfound = 1;
          if ($delegate == 1) {
            dbg("mtx: Delegated."); 
          } else {
            dbg("mtx: Not delegated.");
          }
          if ($participant == 0) {
            dbg("mtx: Found Neutral.");
            $scanner->{mtx_neutral}=1;
            $scanner->{mtx_softfail}=0;
            $scanner->{mtx_hardfail}=0;
          } elsif ($participant == 1) {
            dbg("mtx: Found SoftFail.");
            $scanner->{mtx_neutral}=0;
            $scanner->{mtx_softfail}=1;
            $scanner->{mtx_hardfail}=0;
          } elsif ($participant == 2) {
            dbg("mtx: Found HardFail.");
            $scanner->{mtx_neutral}=0;
            $scanner->{mtx_softfail}=0;
            $scanner->{mtx_hardfail}=1;
          }
        } else {
          dbg("mtx: Unknown policy record found, wildcard DNS record, or new version of MTX?  Ignoring.");
        }
        last; # Protocol says only check first.
      }
    }
    if ($policyfound != 1) {
      dbg("mtx: No policy found at this depth.");
      unless ( $scanner->{mtx_neutral} or $scanner->{mtx_softfail} 
               or $scanner->{mtx_hardfail} ) {
        $scanner->{mtx_none}=1;
      }
      return;
    }
    last unless ($delegate == 1);
  }
}

sub check_mtx {
  my ($self,$scanner) = @_;

  # Sane defaults.  Reduce chance of exploitable flaws.
  $scanner->{mtx_fail}=1;
  $scanner->{mtx_pass}=0;

  dbg("mtx: Doing the necessary DNS lookups.");
  $scanner->{mtx_checked}=1;
  $scanner->{lasthop} = $scanner->{relays_untrusted}->[0];
  if (!defined $scanner->{lasthop}) {
    dbg("mtx: Last untrusted relay not available, fix your SA config, skipping MTX.");
    # The *only* failure that doesn't result in a "fail", because it's 
    # due to SA misconfiguration.  Or all hops being trusted, or something.
    $scanner->{mtx_fail}=0;
    return;
  }
  my $ip = $scanner->{lasthop}->{ip};
  dbg("mtx: Testing IP: $ip (last untrusted relay).");

  my $mtx = '';
  
  {
    my $packet = $res->send($ip, 'PTR');
    unless (defined $packet) {
      dbg('mtx: DNS "PTR" record lookup failed.  You appear to have a DNS problem:  ', $res->errorstring);
      return;
    }
    my @answer = $packet->answer;
    unless (@answer) {
      dbg("mtx: Failed to get PTR record for $ip.");
      $scanner->{mtx_fail}=1;
      $scanner->{mtx_none}=1;
      return;
    }
    # Can't just use the first record because it could be a CNAME with
    # a PTR in there somewhere.
    for my $rr (@answer) {
      if (${$rr}{type} eq 'PTR') {
        $scanner->{hostname} = ${$rr}{ptrdname};
        dbg("mtx: Host name ('PTR' record) is ". $scanner->{hostname} .".");
        my $netip = new Net::IP ($ip);
        my $reverseip = $netip->reverse_ip();
        $reverseip =~ s/\.(in-addr|ip6)\.arpa\.//i;
        unless (defined $reverseip and $reverseip =~ /\./) {
          info("mtx: failed to reverse $ip");
          # REVIEW: maybe $scanner->{mtx_foo} should be set ?????
          return;
        }
        $mtx = $reverseip . '.mtx.' . $scanner->{hostname};
        $scanner->{mtx_record}=$mtx;
        dbg("mtx: Relevant MTX record is: $mtx");
        last; # Protocol says use the first one.   
      }
    }
    if ($mtx eq '') {
      dbg("mtx: Looking up DNS PTR record for sender returned a vailue which did not contain the answer.");
      # Looking up the DNS record for the delivering IP returned an
      # answer, but it contained nothing.  That's pretty freaky.
      # Need to call it a "fail" anyway so spammers don't explot it.
      $scanner->{mtx_fail}=1;
      $scanner->{mtx_none}=1;
      return;
    }

    dbg("mtx: Checking blacklist.");
    foreach my $black_addr (keys %{$scanner->{conf}->{mtx_blacklist}}) {
      my $re = qr/$scanner->{conf}->{mtx_blacklist}->{$black_addr}{re}/i;
      if ($mtx =~ $re) {
        # How can I do this without an array?
        my $bl_score = (@{$scanner->{conf}->{mtx_blacklist}->{$black_addr}{domain}})[0]; 
        dbg("mtx: Blacklisted with score $bl_score and regex $re");
        $scanner->{blacklist_score}=$bl_score;
        last; # Use first matching blacklist entry.
      }
    }
  }
  
  {
    my $packet = $res->send($mtx, 'A');
    unless (defined $packet) {
      dbg('mtx: DNS "A" record lookup failed.  You appear to have a DNS problem:  ', $res->errorstring);
      return;
    }
    my @answer = $packet->answer;
    unless (@answer) {
      dbg("mtx: Failed to get A record for $mtx.");
      $scanner->{mtx_fail}=1;
      return;
    }
    for my $rr (@answer) {
      if (${$rr}{type} eq 'A') {
        my $address = ${$rr}{address};
        unless (defined $address) {
          dbg("mtx: A record exists but has no value.  I don't think this is possible.");
          # Make sure it doesn't get exploited, just in case.
          $scanner->{mtx_fail}=1;
          return;
        }
        dbg("mtx: MTX record value: $address.");
        if ($address =~ m#^127\.\d{1,3}\.\d{1,3}\.(0|1)$#) { ##
          my $mtxvalue = $1;
          if ($mtxvalue == 1) {
            dbg("mtx: MTX record value indicates legit server.  That's the only pass.");
            $scanner->{mtx_pass}=1;
            $scanner->{mtx_fail}=0;
            return;
          } elsif ($mtxvalue == 0) {
            dbg("mtx: MTX record value indicates non-legit server.  That's a fail.");
            $scanner->{mtx_fail}=1;
            $scanner->{mtx_hardfail}=1;
            return;
          } else {
            dbg("mtx: Somebody introduced a bug.");
            die "mtx: Somebody introduced a bug.";
          }
        } else {
          dbg("mtx: Unknown MTX record value found.  Wildcard DNS record or new version of MTX?  Ignoring.");
        }
        last; # Protocol says only check first.
      }
    }
    dbg("mtx: No known MTX record value found, fail.");
    $scanner->{mtx_fail}=1;
    return;
  }
}


sub set_config {
  my ($self, $conf) = @_;
  my @cmds;

  push (@cmds, {
    setting => 'mtx_blacklist',
    code => sub {
      my ($self, $key, $value, $line) = @_;
      local ($1,$2);
      unless (defined $value and $value !~ /^$/) {
        return $Mail::SpamAssassin::Conf::MISSING_REQUIRED_VALUE;
      }
      # It is important to not accept negative scores on the blacklist,
      # because these hostnames can effortlessly beforged by the IP owner.
      unless (defined $value and $value =~ /^(\S+)\s+([\d\.]+)$/) {
        return $Mail::SpamAssassin::Conf::INVALID_VALUE;
      }
      my $address = $1;
      my $score = $2;
      $self->{parser}->add_to_addrlist_rcvd('mtx_blacklist', $address, $score);
    }
  });

  return($conf->{parser}->register_commands(\@cmds));
}

sub check_mtx_blacklist {
  my ($self, $scanner) = @_;
  &check_mtx unless $scanner->{mtx_checked};
  my @cmds;
  my $score = $scanner->{blacklist_score};

  if($score) {
    my $description = $scanner->{conf}->{descriptions}->{MTX_BLACKLIST};
    $description .= "  Score $score.";
    $scanner->{conf}->{descriptions}->{MTX_BLACKLIST} = $description;

    # Set the score.
    $scanner->got_hit("MTX_BLACKLIST", "", score => $score);
    for my $set (0..3) {
      $scanner->{conf}->{scoreset}->[$set]->{"MTX_BLACKLIST"} = sprintf("%0.3f", $score); 
    }
  }
  
  return 0;
}

1;
