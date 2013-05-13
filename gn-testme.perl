#!/usr/bin/perl -w

use lib qw(.);
use GermaNet::Flat;
use File::Basename qw(basename);
#use Getopt::Long qw(:config no_ignore_case);
#use Pod::Usage;

use open qw(:std :utf8);

##==============================================================================
## constants
our $prog = basename($0);

##==============================================================================
## command-line
our ($infile,@terms) = @ARGV;
foreach (@terms) { utf8::decode($_) if (!utf8::is_utf8($_)); }
die("Usage: $prog INFILE TERM(s)\n") if (@ARGV < 2);

##==============================================================================
## MAIN
my $gn = GermaNet::Flat->load($infile)
  or die("$prog: failed to load '$infile': $!");
my $inmode = $gn->{inmode} || 'unknown';

print STDERR "> src[$inmode] = $infile\n";
print STDERR "> term(s) = ", join(' ', @terms), "\n";
my $rel = $gn->{rel};

my $lex = $gn->orth2lex(\@terms);
die("$prog: no lexical id(s) for term(s) ", join(' ', @terms)) if (!$lex || !@$lex);
print STDERR "> lex id(s) = ", join(' ', @$lex), "\n";

my $syn = $gn->lex2syn($lex);
die("$prog: no synset id(s) for term(s) ", join(' ', @terms)) if (!$syn || !@$syn);
print STDERR "> syn id(s) = ", join(' ', @$syn), "\n";

##-- hyperonyms (superclasses)
my $isa_syn = $gn->hyperonyms($syn);
print STDERR "> hyperonym syn id(s) = ", join(' ', @$isa_syn), "\n";
my $isa_lex = $gn->syn2lex($isa_syn);
print STDERR "> hyperonym lex id(s) = ", join(' ', @$isa_lex), "\n";
my $isa_orth = $gn->lex2orth($isa_lex);
print STDERR "> hyperonym form(s) = ", join(' ', @$isa_orth), "\n";

##-- hyponyms (subclasses)
my $asi_syn = $gn->hyponyms($syn);
print STDERR "> hyponym syn id(s) = ", join(' ', @$asi_syn), "\n";
my $asi_lex = $gn->syn2lex($asi_syn);
print STDERR "> hyponym lex id(s) = ", join(' ', @$asi_lex), "\n";
my $asi_orth = $gn->lex2orth($asi_lex);
print STDERR "> hyponym form(s) = ", join(' ', @$asi_orth), "\n";
