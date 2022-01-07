
# MTX plugin for SpamAssassin (v3.2.5)
# (c) Darxus@ChaosReigns.com, released under the GPL.
# 2010-02-10 Initial release.

=head1 NAME

MTX - MTX

=head1 SYNOPSIS

  loadplugin     Mail::SpamAssassin::Plugin::MTX
  header         MY_TEST_PLUGIN eval:check_test_plugin()

loadplugin Mail::SpamAssassin::Plugin::MTX
header MTX_PASS eval:check_mtx_pass()
header MTX_FAIL eval:check_mtx_fail()
score MTX_PASS -1
score MTX_FAIL 0.001
blacklist_from *@examplespammerdomain.com

http://www.chaosreigns.com/mtx/

=head1 DESCRIPTION

Write the above lines in the synopsis to
C</etc/spamassassin/local.cf>.

=cut

package Mail::SpamAssassin::Plugin::MTX;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger; # dbg()
use strict;
use warnings;
use bytes;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

# constructor: register the eval rule
sub new {
  my $class = shift;
  my $mailsaobject = shift;

  # some boilerplate...
  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  $self->register_eval_rule ("check_mtx_pass");
  $self->register_eval_rule ("check_mtx_fail");

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
  
  my $res = Net::DNS::Resolver->new;
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
    for my $rr (@answer) {
      if (${$rr}{type} eq 'PTR') {
        $hostname = ${$rr}{ptrdname};
        dbg("mtx: Host name ('A' record) is $hostname.");
        $mtx = join('.',reverse(split('\.',$ip))) . '.mtx.' . $hostname;
        dbg("mtx: Relevant MTX record is: $mtx");
      }
    }
    if ($mtx eq '') {
      dbg("mtx: Failed to calculate MTX record.  This is probably a bug.");
      return;
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
      dbg("Failed to get A record for $mtx.");
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
          dbg("mtx: Unknown MTX record value found.  Wildcard or new version?  Ignoring.");
        }
      }
    }
    dbg("mtx: No known MTX record value found, fail.");
  }
}

1;
