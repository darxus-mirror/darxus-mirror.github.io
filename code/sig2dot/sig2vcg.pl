#!/usr/bin/perl

# sig2vcg (c) Darxus@ChaosReigns.com, released under the GPL
# Download from: http://www.chaosreigns.com/debian-keyring
#
# Parses the (gpg) debian-keyring
# (http://www.debian.org/Packages/unstable/misc/debian-keyring.html) to a format# suitable for use by dot or neato (package name graphviz,
# http://www.research.att.com/sw/tools/graphviz/) like so:
#
# gpg --list-sigs --keyring /usr/share/keyrings/debian-keyring.gpg | ./sig2vcg.pl > debian-keyring.dot
# neato -Tps debian-keyring.dot > debian-keyring.neato.dot.ps
# dot -Tps debian-keyring.dot > debian-keyring.dot.dot.ps


while ($line = <STDIN>)
{
  chomp $line;
  if ($line =~ m#([^ ]+) +[^ ]+ +[^ ]+ +([^<]+)#)
  {
    $type = $1;
    $name = $2;
    chop $name;
    #print "type:$type:name:$name:\n";

    if ($type eq "pub")
    {
      $owner = $name; 
    }

    if ($type eq "sig" and $name ne $owner and $name ne '[User id not found')
    {
      push (@{$sigs{$owner}},$name);
      push (@names,$name,$owner);
    }
  } else {
    print STDERR "Couldn't parse: $line\n";
  }
}

print"graph: {
";

#width: 1000
#height: 900
#splines: yes



undef %saw;
@saw{@names} = ();
@names = keys %saw;
undef %saw;

#print "\nSigners:\n";
#print join("\n",@names),"\n";


for $owner (sort keys %sigs)
{
  undef %saw;
  @saw{@{$sigs{$owner}}} = ();
  @{$sigs{$owner}} = keys %saw;
  undef %saw;

  #print "\n\nOwner: $owner\n",scalar(@{$sigs{$owner}})," Signers:\n";
  #print join("\n",@{$sigs{$owner}});
  #print STDERR scalar(@{$sigs{$owner}})," $owner\n";
  $count{$owner} = scalar(@{$sigs{$owner}});


}

for $name (@names)
{
  if ($count{$name} > 20)
  {
    print "node: { title: \"$name\" color: red }\n";
  } elsif ($count{$name} > 8)
  {
    print "node: { title: \"$name\" color: blue }\n";
  } else {
    print "node: { title: \"$name\" }\n";
  }
}

for $owner (sort keys %sigs)
{
  for $name (@{$sigs{$owner}})
  {
    print "bentnearedge: { sourcename: \"$name\" targetname: \"$owner\" }\n";
  }
}

print "}\n";


