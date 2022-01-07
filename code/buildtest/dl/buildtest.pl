#!/usr/bin/perl

# Args:
# (none): For each repo with an updated commit, build everything, and update commit.log.
# latest: Try the latest commits of everything
# latestgood: Try the latest commits of everything for which the most
#   recent commit is not bad, and for those use the last known good commit.
# force: Build without any pulling.

# TODO:
# * Handling of various options around line 347 is bad.
# * repo: mode builds the last known good version of the target repo, not the latest
# * latestgood should only build once, stop checking for new repos after

use strict;
use warnings;

my $debug = 0;

use List::Util qw(first max maxstr min minstr reduce shuffle sum);
$| = 1; # don't buffer output

my $conf = $ARGV[0];
die "Specify config file as first argument." unless ($conf);
my $force = 0;
my $latest = 0;
if (defined $ARGV[1] and ($ARGV[1] eq 'force' or $ARGV[1] =~ m#^repo#) ) {
  $force = 1;
}
if (defined $ARGV[1] and ($ARGV[1] eq 'latest' or $ARGV[1] eq 'latestgood') ) {
  $latest = 1;
}


my %lkg = (); # last known good
my %lkb = (); # last known bad
our %commit = ();
our $newrepo = '';
our $newcommit = '';
our $repo = '';
our $date = `date +%F-%H-%M`;
chomp $date;
our %url = ();
our %branch = ();
our %check = ();
our %args = ();
our %dep = ();

my $installdir = '';
my $sourcedir = '';
my $email = '';
my $prebuild = '';
open CONF, "<$conf" or die "Couldn't read $conf: $!";
#my @conflines = <CONF>;
my @conflines = ();
our @repos = ();
while (my $line = <CONF>) {
  chomp $line;
  next if ($line =~ /^#/);
  if ($line =~ m#^installdir=(.*)$#) {
    $installdir = $1;
    print "Installing to $installdir\n" if $debug;
  } elsif ($line =~ m#^sourcedir=(.*)$#) {
    $sourcedir = $1;
    print "Source directory $sourcedir\n" if $debug;
  } elsif ($line =~ m#^email=(.*)$#) {
    $email = $1;
    print "Contact email is $email\n" if $debug;
  } elsif ($line =~ m#^repo=(.*)$#) {
    my $url = $1;
    $url =~ s/\.git//;
    $repo = (reverse(split('/',$url)))[0];
    print "\nrepo:$repo:\n" if $debug;
    print "url:$url:\n" if $debug;
    push @repos, $repo;
    $url{$repo} = $url;
  } elsif ($line =~ m#^args=(.*)$#) {
    $args{$repo} = $1;
    print "$repo args:$args{$repo}:\n" if $debug;
  } elsif ($line =~ m#^branch=(.*)$#) {
    $branch{$repo} = $1;
    print "$repo branch:$branch{$repo}:\n" if $debug;
  } elsif ($line =~ m#^prebuild=(.*)$#) {
    $prebuild = $1;
    print "prebuild:$prebuild:\n" if $debug;
  } elsif ($line =~ m#^check=(.*)$#) {
    $check{$repo} = $1;
    print "$repo check:$check{$repo}:\n" if $debug;
  } elsif ($line =~ m#^dep=(.*)$#) {
    my $dep = $1;
    push @{$dep{$repo}}, $dep;
    print "$repo deps:".join(',', @{$dep{$repo}}).":\n" if $debug;
  } elsif ($line =~ m#^nocheck$#) {
    $check{$repo} = 'nocheck';
    print "$repo check:$check{$repo}\n" if $debug;
  } elsif ($line =~ m#^\s*$#) {
  } else {
    die "Couldn't parse config line: $line\n";
  }
}
close CONF;

my @allrepos = shuffle(@repos);

our $mainrepo = '';
if ($ARGV[1] =~ m#^repo:(.*)$#) {
  $mainrepo = $1;
  print "Building only $mainrepo and its dependencies.\n";
  @repos = ();
  push @repos, $mainrepo, &getdeps($mainrepo);
  @repos = &uniq(@repos);
  @repos = shuffle(@repos);
#  print "Building repos: " . join(", ", @repos) . "\n";
#  exit; ######################################################################
} else {
  @repos = @allrepos;
}

my %done = ();
my @order = ();
while (my $repo = shift @repos) {
  print "Checking $repo.\n" if $debug;
  if (exists $dep{$repo}) {
    my $ready = 1;
    for my $dep (@{$dep{$repo}}) {
      print "  $repo depends on $dep.\n" if $debug;
      unless (exists $url{$dep}) {
        die "I don't know the url for $dep.\n";
      }
      if (exists $done{$dep}) {
        print "    It is done\n" if $debug;
      } else {
        print "    It is not done, skipping $repo\n" if $debug;
        $ready = 0;
      }
    }
    if ($ready == 1) {
      print "  All deps done, using $repo.\n" if $debug;
      push @order, $repo;
      $done{$repo} = 1;
    } else {
      push @repos, $repo;
    }
  } else {
    print "  No deps, using $repo.\n" if $debug;
    push @order, $repo;
    $done{$repo} = 1;
  }
}
undef %done;
@repos = @order;
undef @order;

#@repos = qw( glproto harfbuzz randrproto x11proto inputproto xproto libX11 drm wayland proto libxkbcommon libpciaccess at-spi2-core libXdmcp macros pthread-stubs kbproto fontconfig libXau glib pixman libxcb mesa cairo weston xserver gobject-introspection xf86-video-ati pango gdk-pixbuf atk at-spi2-atk gtk+);

#@repos = qw( pixman fontconfig pthread-stubs macros libpciaccess inputproto llvm proto drm randrproto libffi recordproto libxkbcommon dri2proto libxtrans glproto kbproto xproto wayland libXau libXdmcp glib x11proto libxcb libX11 harfbuzz libXext libXi libXfixes libXtst at-spi2-core libXdamage mesa cairo gobject-introspection atk gdk-pixbuf at-spi2-atk xserver xf86-video-wlshm weston pango gtk+ xf86-video-intel xf86-video-ati );

#@repos = qw{ libffi glib };

#@repos = qw{ proto pixman fontconfig pthread-stubs libffi macros libxtrans glproto libxkbcommon inputproto wayland randrproto kbproto recordproto libpciaccess glib xproto drm dri2proto libXau harfbuzz libXdmcp x11proto libxcb libX11 libXext libXfixes libXi libXdamage libXtst mesa };

#@repos = qw{ mesa };

print "Build order: " . join(', ', @repos) . "\n";

if (-e "$sourcedir/buildtest.lock") {
  open IN, "$sourcedir/buildtest.lock" or die "$sourcedir/buildtest.lock exists but I couldn't read it?: $!";
  my $lockpid = <IN>;
  close IN;
  chomp $lockpid;
  my $lockprocess = `ps -p $lockpid -o comm=`;
  chomp $lockprocess;
  if ($lockprocess eq 'buildtest.pl') {
    open MAIL, "| /usr/bin/mail -s 'Build test already running.' $email";
    print MAIL "Build test failed because $sourcedir/buildtest.lock already existed.\n";
    close MAIL;
    die "Failed because $sourcedir/buildtest.lock already exists, process is '$lockprocess'.";
  } else {
    open MAIL, "| /usr/bin/mail -s 'Build test stale lock file.' $email";
    print MAIL "$sourcedir/buildtest.lock already existed, but the PID is now '$lockprocess', so continuing.\n";
    close MAIL;
    print "$sourcedir/buildtest.lock already existed, but the PID is now '$lockprocess', so continuing.\n";
    unlink "$sourcedir/buildtest.lock" or die "Couldn't delete $sourcedir/buildtest.lock: $!";
  }
}

if ($installdir eq '' or $sourcedir eq '' or $email eq '') {
  die "installdir, sourcedir, and email need to be specified in the config file.";
}

$ENV{PKG_CONFIG_PATH}="$installdir/lib/pkgconfig/:$installdir/share/pkgconfig/";
$ENV{ACLOCAL}="aclocal -I $installdir/share/aclocal";
#I think needing this is a bug in at-spi2-core
#$ENV{C_INCLUDE_PATH}="$installdir/include";
$ENV{LIBRARY_PATH}="$installdir/lib";
$ENV{PATH}="$installdir/bin:$ENV{PATH}"; # Needed by gtk for $installdir/bin/gdk-pixbuf-pixdata
$ENV{LD_LIBRARY_PATH}="$installdir/lib";
#$ENV{MAKEFLAGS}=''; # I don't actually want to multi-thread this
#$ENV{MAKEFLAGS}='-j 5'; # use 5 threads
#$ENV{MAKEFLAGS}='-j 1'; # use 5 threads
$ENV{XDG_RUNTIME_DIR}="$ENV{HOME}/tmp";
$ENV{DISPLAY}=":0";


unless (-d $sourcedir            ) { mkdir $sourcedir;       }
unless (-d "$sourcedir/log"      ) { mkdir "$sourcedir/log"; }
unless (-d "$sourcedir/log/$date") { mkdir "$sourcedir/log/$date"; }

open OUT, ">$sourcedir/buildtest.lock" or die "Couldn't write to $sourcedir/buildtest.lock: $!";
print OUT "$$\n";
close OUT;

open OUT, ">$sourcedir/log/$date/order.txt" or &cleanup("Couldn't write to $sourcedir/log/$date/order.txt: $!");
print OUT join(', ', @repos) . "\n";
close OUT;

my %repostate = ();
if (-e "$sourcedir/commit.log") {
  open IN, "<$sourcedir/commit.log" or &cleanup("Couldn't read $sourcedir/commit.log: $!");
  while (my $line = <IN>) {
    chomp $line;
    my ($date, $commit, $goodbad, $repo) = split(' ',$line);
    if ($goodbad eq 'good') {
      $lkg{$repo} = $commit;
      $repostate{$repo} = 'good';
    } elsif ($goodbad eq 'bad') {
      $lkb{$repo} = $commit;
      $repostate{$repo} = 'bad';
    }
  }
  close IN;
}


#if ($force or $latest) {
if ($force) {
  print "Forcing build.\n";
  &build;
  &updatelkg;
} else {
  for $repo (@repos) {
    $branch{$repo} = 'master' unless (exists $branch{$repo});
    $newrepo = $repo;
    print "Checking repo: $newrepo\n";
    $newcommit = '';
    my $clone = 0;
    my $commit = '';
    if (-d "$sourcedir/$newrepo") {
      chdir "$sourcedir/$newrepo" or &cleanup("Couldn't cd $sourcedir/$newrepo: $!");
      &run ("git checkout -q $branch{$repo}", 'checkout');
      #&run ("git pull > pull.out", 'pull');
      &run ("git pull > pull.out", 'pull') unless ($newrepo eq 'llvm');
      $commit = `git log -1 --pretty=format:"%H"`;
      $newcommit = $commit;
    } else {
      chdir "$sourcedir" or &cleanup("Couldn't cd $sourcedir: $!");
      print "Downloading.\n";
      &run ("git clone $url{$repo}", 'clone');
      chdir "$sourcedir/$newrepo" or &cleanup("Couldn't cd $sourcedir/$newrepo: $!");
      &run ("git checkout -q $branch{$repo}", 'checkout');
      $commit = `git log -1 --pretty=format:"%H"`;
      $newcommit = $commit;
      #$clone = 1;
    }
    if (((! exists $lkg{$newrepo} or $commit ne $lkg{$newrepo}) and 
        (! exists $lkb{$newrepo} or $commit ne $lkb{$newrepo})) or $clone) {
      print "$newrepo is new, rebuild ALL THE THINGS, commit $commit\n";
      if ($latest) {
        $newrepo = '' ;
        $newcommit = '';
      }
      &build();
  
      print "Full rebuild for $newrepo commit $commit successful.\n\n";
      unless ($latest) {
        $lkg{$newrepo} = $commit;
        open LKG, ">>$sourcedir/commit.log" or &cleanup("Couldn't write to $sourcedir/commit.log: $!");
        print LKG "$date $commit good $newrepo\n";
        close LKG;
      }
      &updatelkg;
      #last; ###############################################################
    }
  }
}

unlink "$sourcedir/buildtest.lock" or &cleanup("Couldn't delete $sourcedir/commit.log: $!");

print "Done.\n\n";

exit; #######################################################

sub build {
  if (-d $installdir)                     { &run ("rm -rf $installdir", 'rm'); }
  unless (-d $installdir)                 { mkdir $installdir; }
  unless (-d "$installdir/share")         { mkdir "$installdir/share"; }
  unless (-d "$installdir/share/aclocal") { mkdir "$installdir/share/aclocal"; }

  unless ($prebuild eq '') {
    $prebuild =~ s/\$installdir/$installdir/g;
    print "Running prebuild: $prebuild\n";
    system($prebuild);
  }

  my $repocount = scalar(@repos);
  my $reponum = 0;
  for $repo (@repos) {
    $reponum++;
    # Bug in at-spi2-core (https://bugs.freedesktop.org/show_bug.cgi?id=60911) and mesa (https://bugs.freedesktop.org/show_bug.cgi?id=61919):
    #if ($repo eq 'at-spi2-core' or $repo eq 'mesa') {
    if ($repo eq 'at-spi2-core') {
      $ENV{C_INCLUDE_PATH}="$installdir/include";
    } else {
      delete $ENV{C_INCLUDE_PATH};
    }
    unless (exists $args{$repo}) {
      $args{$repo} = "./autogen.sh --prefix=$installdir"
    }
    $args{$repo} =~ s/\$installdir/$installdir/g;
    $branch{$repo} = 'master' unless (defined $branch{$repo});
    print "\n" if $debug;
    print "Building repo $reponum/$repocount: $repo\n";
    chdir $sourcedir or &cleanup("Couldn't cd to $sourcedir: $!");
    if (! -d $repo) {
      chdir "$sourcedir" or &cleanup("Couldn't cd $sourcedir: $!");
      print "Downloading.\n";
      &run ("git clone $url{$repo}", 'clone');
      chdir "$sourcedir/$repo" or &cleanup("Couldn't cd $sourcedir/$repo: $! (194)");
      &run ("git checkout -q $branch{$repo}", 'checkout');
    } else {
      chdir "$sourcedir/$repo" or &cleanup("Failed to chdir to $sourcedir/$repo: $!");
      unless ($newrepo eq $repo) {
        if ($latest) {
          if (exists $repostate{$repo} and $repostate{$repo} eq 'bad') {
            &run ("git checkout -q $lkg{$repo}", 'checkout');
          } else {
            &run ("git checkout $branch{$repo}", 'checkout');
            #&run ("git pull > pull.out", 'pull');
            &run ("git pull > pull.out", 'pull') unless ($repo eq 'llvm');
          }
        } elsif (exists $lkg{$repo}) {
          &run ("git checkout -q $lkg{$repo}", 'checkout');
        } elsif ($branch{$repo} eq '') {
          &run ("git checkout $branch{$repo}", 'checkout');
        }
      }
      &run ("git clean -xfd > clean.out", 'clean');
    }
    chdir "$sourcedir/$repo" or &cleanup("Failed to chdir to $sourcedir/$repo: $!");
    $commit{$repo} = `git log -1 --pretty=format:"%H"`;
    for my $command (split(';', $args{$repo})) {
      &run ("$command > configure.out 2>&1", 'configure');
    }
    &run ("make > make.out 2>&1", 'make');
    $check{$repo} = 'make check' unless (exists $check{$repo});
    unless ($check{$repo} eq 'nocheck') {
      &run ("$check{$repo} > make_check.out 2>&1", 'make_check')
    }
    &run ("make install > make_install.out 2>&1", 'make_install');
#    $commit{$repo} = `git log -1 --pretty=format:"%H"`;
#    print "  $commit{$repo}\n";
#    print "  $repo build successful.\n";
    #cp -a config.status ~/source/log/2013-03-05-18-46/glib-config.status
    #cp: cannot stat `config.status': No such file or directory
    if (-e "config.status") {
      system("cp -a config.status $sourcedir/log/$date/$repo-config.status");
    }
  }

  #system("cp -a $installdir $installdir.good.new");
  #system("mv $installdir.good $installdir.good.old");
  #system("mv $installdir.good.new $installdir.good");
  #system("rm -rf $installdir.good.old");

  open OUT, ">$sourcedir/log/$date/commits.good.txt" or &cleanup("Couldn't write to $sourcedir/log/$date/commits.good.txt: $!");
  for my $repo (sort keys %commit) {
    print OUT "$commit{$repo} $repo\n";
  }
  close OUT;
  system ("cp -a $sourcedir/log/$date/commits.good.txt $installdir/");
  
  # Don't do this if repo: arg, or if nothing was built due to nothing new
  
  unless ($ARGV[1] =~ m#^repo#) {
    print "Copying $installdir to $installdir.good .\n";
    system("mv $installdir.good $installdir.good.old");
    system("mv $installdir $installdir.good");
    system("rm -rf $installdir.good.old");
  }
}

sub run {
  my $command = shift;
  my $logfile = shift or &cleanup("specify log file as second arg to run().");
  print "  $command\n" if $debug;
  $command = "$command > $sourcedir/log/$date/$repo-$logfile.log 2>&1";
  unless (system($command) == 0 or $logfile eq 'pull') {
    print "Main repo: $mainrepo\n";
    print "Build order: ". join(', ', @repos) . "\n";

    open MAIL, "| /usr/bin/mail -s 'Build test failed: $repo / $newrepo.' $email";
    print MAIL "Command: $command\nBuilding: $repo\nCommit: $newcommit\nUpdated repo: $newrepo\nConfig: $conf\n";
    print MAIL "Main repo: $mainrepo\n";
    print MAIL "Build order: ". join(', ', @repos) . "\n";
    close MAIL;

    open LKG, ">>$sourcedir/commit.log" or &cleanup("Couldn't write to $sourcedir/commit.log: $!");
#    my $date = `date +%F-%H-%M`;
#    chomp $date;
    print LKG "$date $newcommit bad $newrepo\n";
    close LKG;

    open OUT, ">$sourcedir/log/$date/commits.bad.txt" or &cleanup("Couldn't write to $sourcedir/log/$date/commits.good.txt: $!");
    for my $repo (sort keys %commit) {
      print OUT "$commit{$repo} $repo\n";
    }
    close OUT;

    #exit unless ($command =~ m#^git pull#);
    &cleanup("Build test failed, rebuilding $repo for $newrepo commit $newcommit config $conf\nCommand: $command\nBuilding: $repo\nCommit: $newcommit\nUpdated repo: $newrepo\nConfig: $conf");
  }
}

sub updatelkg {
  open LKG, ">>$sourcedir/commit.log" or &cleanup("Couldn't write to $sourcedir/commit.log: $!");
  for my $checkrepo (sort keys %commit) {
    #unless (exists $lkg{$checkrepo} or $checkrepo eq $newrepo) {
    unless ($checkrepo eq $newrepo or (exists($lkg{$checkrepo}) and $lkg{$checkrepo} eq $commit{$checkrepo})) {
      $lkg{$checkrepo} = $commit{$checkrepo};
      print LKG "$date $commit{$checkrepo} good $checkrepo\n";
    }
  }
  close LKG;
}

sub cleanup {
  my $arg = shift or print "cleanup() needs an argument of a reason for dieing.\n";
#  print "$arg - disabled dieing\n";
  unlink "$sourcedir/buildtest.lock" or die "Couldn't delete $sourcedir/buildtest.lock: $!";
  die $arg;
}

sub getdeps {
  my $repo = shift;
  my @ret = ();
  #die "Called getdeps() on non-existant repo $repo.\n" unless (exists $dep{$repo});
  for my $dep (@{$dep{$repo}}) {
    #push @ret, $dep, &getdeps($dep);
    push @ret, $dep, &getdeps($dep);
    @ret = &uniq(@ret);
#    print "Dependencies for $dep = " . join(', ', @ret) . "\n";
  }
  return @ret;
}

# from http://stackoverflow.com/questions/7651/how-do-i-remove-duplicate-items-from-an-array-in-perl
sub uniq {
    return keys %{{ map { $_ => 1 } @_ }};
}
