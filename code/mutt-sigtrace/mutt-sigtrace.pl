#!/usr/bin/perl

# mutt-sigtrace v0.3, (c) Darxus@ChaosReigns.com, released under the GPL.
# http://www.ChaosReigns.com/code/mutt-sigtrace/

$linenum = 0;

$myid = shift @ARGV;

open (CMD, "@ARGV 2>&1 >/dev/null|");

while ($line=<CMD>)
{
  print STDERR "$line";
  if ($line =~ "key ID")
  {
    $id = (reverse(split(' ',$line)))[0];
  }
}

if ($id)
{
  #$path = `~/sigtrace.pl 0E9FF879 $id|grep "hop"`;
  $path = `~/sigtrace.pl $myid $id`;
  if ($path)
  {
    print STDERR "$path\n"
  } else {
    print STDERR "No path found.\n";
  }
} else {
  print STDERR "No id found\n";
}
