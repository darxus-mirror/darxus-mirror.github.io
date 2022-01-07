
# MTX plugin for SpamAssassin (v3.2.5)
# (c) Darxus@ChaosReigns.com, released under the GPL.
# http://www.chaosreigns.com/mtx/
#
# 2010-02-10 Initial release.
# 2010-02-12 Implemented blacklisting, switched to SA's DnsResolver
#
# TODO
# * Switch to Mail::SpamAssassin::DnsResolver::bgsend

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

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

sub new {
  my $class = shift;
  my $mailsaobject = shift;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  $self->register_eval_rule ("check_mtx_pass");
  $self->register_eval_rule ("check_mtx_fail");
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

sub check_mtx {
  my ($self,$scanner) = @_;

  dbg("mtx: Doing the necessary DNS lookups.");
  $scanner->{mtx_checked}=1;
  my $lasthop = $scanner->{relays_external}->[0];
  if (!defined $lasthop) {
    dbg("mtx: Last untrusted relay not available, skipping MTX.");
    return;
  }
  my $ip = $lasthop->{ip};
  dbg("mtx: Testing IP: $ip (last untrusted relay).");

  my $hostname = '';
  my $mtx = '';
  
  #my $res = Net::DNS::Resolver->new;
  my $res = Mail::SpamAssassin::DnsResolver->new;
  {
    my ($packet, $err) = $res->send($ip, 'PTR');
    if ($err) {
      dbg("mtx: Error retrieving PTR record: $err");
      $scanner->{mtx_fail}=1;
      return;
    }
    my @answer = $packet->answer;
    unless (@answer) {
      dbg("mtx: Failed to get PTR record for $ip.");
      $scanner->{mtx_fail}=1;
      return;
    }
    #for my $rr (@answer) {
    my $rr = (@answer)[0]; { # Protocol says use the first one.
      if (${$rr}{type} eq 'PTR') {
        $hostname = ${$rr}{ptrdname};
        dbg("mtx: Host name ('A' record) is $hostname.");
        $mtx = join('.',reverse(split('\.',$ip))) . '.mtx.' . $hostname;
        $scanner->{mtx_record}=$mtx;
        dbg("mtx: Relevant MTX record is: $mtx");
        last; 
      }
    }
    if ($mtx eq '') {
      dbg("mtx: Failed to calculate MTX record.  This is probably a bug.");
      return;
    }

    dbg("mtx: Checking blacklist.");
    foreach my $black_addr (keys %{$scanner->{conf}->{mtx_blacklist}}) {
      my $re = qr/$scanner->{conf}->{mtx_blacklist}->{$black_addr}{re}/i;
      #dbg("mtx: Blacklist entry: $re");
      if ($mtx =~ $re) {
        my $bl_score = (@{$scanner->{conf}->{mtx_blacklist}->{$black_addr}{domain}})[0]; # How can I do this without an array?
        dbg("mtx: Blacklisted with score $bl_score and regex $re");
        $scanner->{blacklist_score}=$bl_score;
        last;
      }
    }
  }
  
  {
    my ($packet, $err) = $res->send($mtx, 'A');
    if ($err) {
      dbg("mtx: Failed to get A record: $err");
      $scanner->{mtx_fail}=1;
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
          return;
        }
        dbg("mtx: MTX record value: $address.");
        if ($address =~ m#^127\.\d{1,3}\.\d{1,3}\.1$#) { ##
          $scanner->{mtx_pass}=1;
          dbg("mtx: MTX record value indicates legit server.  That's a pass.");
          return;
        } elsif ($address =~ m#^127\.\d{1,3}\.\d{1,3}\.0$#) { ##
          $scanner->{mtx_fail}=1;
          dbg("mtx: MTX record value indicates non-legit server.  That's a fail.");
          return;
        } else {
          dbg("mtx: Unknown MTX record value found.  Wildcard DNS record or new version of MTX?  Ignoring.");
        }
      }
    }
    dbg("mtx: No known MTX record value found, fail.");
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
      unless (defined $value && $value !~ /^$/) {
        return $Mail::SpamAssassin::Conf::MISSING_REQUIRED_VALUE;
      }
      unless (defined $value && $value =~ /^(\S+)\s+([\d\.]+)$/) {
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
      $scanner->{conf}->{scoreset}->[$set]->{"MTX_BLACKLIST"} = sprintf("%0.3f", $score); # I bet this shouldn't be all 4.
    }
  }
  
  return 0;
}

1;

