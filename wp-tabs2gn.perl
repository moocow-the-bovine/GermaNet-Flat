#!/usr/bin/perl -w

use Getopt::Long qw(:config no_ignore_case);
use Encode qw(encode_utf8 decode_utf8);
use POSIX qw(strftime);
use File::Basename qw(basename dirname);
use strict;

use open qw(:std :utf8);

BEGIN {
  select STDERR; $|=1; select STDOUT;
}

##======================================================================
## command-line
my ($help);

my $outfile = '-';
my $dbstamp = undef; ##-- default: file mtime or current timestamp

GetOptions(
	   'help|h' => \$help,
	   'db-version|dbversion|dbv|V=s' => \$dbstamp,
	   'output|outfile|out|of|o=s' => \$outfile,
	  );
if ($help || !@ARGV) {
  print STDERR <<EOF;

Usage: $0 [OPTIONS] DBFILE

 Purpose:
  Generate text file suitable for use with GermaNet::Flat from a flat
  list of TAB-separated SUBCLASS "\t" SUPERCLASS pairs as arising
  from a Wikipedia category dump.

 Options:
  -help			  # this help message
  -o     , -output OUT	  # set output file (default=- (stdout))
  -V     , -dbversion VER # set database version (default: from DB mtime)

EOF
  exit 0;
}
my $infile = @ARGV ? $ARGV[0] : undef;


##======================================================================
## MAIN

##--------------------------------------------------------------
## extract: dbstamp

##-- ensure we've got a db timestamp
if (!defined($dbstamp)) {
  my $mtime = defined($infile) ? (stat($infile))[9] : time;
  $dbstamp = basename($infile||'-').'@'.POSIX::strftime("%FT%T%z", localtime($mtime));
}

##--------------------------------------------------------------
## extract relations
##  + orth2lex:ORTH->LEX*    , lex2orth
##  + lex2syn:LEX->SYN*      , syn2lex
##  + has_hypernym:SYN->SYN* , has_hyponym:SYN->SYN*
##  + dbversion:''->VERSION

my (%rel);
my ($sub,$sup,$subid,$supid);

my $nsyn = 0;

## $id = ensure_syn($TERM)
##  + ensures a orthographic entry, a lexicon entry, and a synset for $TERM, returns new synset id
my ($w,$id);
sub ensure_syn {
  $w = shift;
  $w =~ s/\s/_/g; ##-- no whitespace allowed in DB keys

  ##-- check for existing id
  if (defined($id=$rel{"orth2lex:$w"})) {
    $id =~ s/^l//;
    return $id;
  }

  ##-- add new id
  $id = ++$nsyn;
  #if (($nsyn % 100000)==0) { print STDERR "+"; } ##-- DEBUG
  $rel{"orth2lex:$w"}    = "l$id";
  $rel{"lex2orth:l$id"} .= " $w";
  $rel{"lex2syn:l$id"}  .= " s$id";
  $rel{"syn2lex:s$id"}  .= " l$id";
  return $id;
}


##-- get relations: (orth<->lex), (lex<->syn), has_hypernym, has_hyponym
print STDERR "$0: processing input(s)\n";
while (defined($_=<>)) {
  #if (($. % 100000)==0) { print STDERR "."; } ##-- DEBUG
  chomp;
  next if (/^\s*$/);

  ($sub,$sup) = split(/\t/,$_,2);
  $subid = ensure_syn($sub);
  $supid = ensure_syn($sup);
  $rel{"has_hypernym:s$subid"} .= " s$supid";
  $rel{"has_hyponym:s$supid"}  .= " s$subid";
}

##--------------------------------------------------------------
## sanitize relations
print STDERR "$0: sanitizing relations\n";

## @uniq =      luniq(@list)
## @uniq = $gn->luniq(@list)
sub luniq {
  shift if (@_ && UNIVERSAL::isa($_[0],__PACKAGE__));
  my ($prev);
  return grep {($prev//'') eq ($_//'') ? qw() : ($prev=$_)} sort @_;
}

##-- sanitize
foreach (values %rel) {
  s/\s+$//;
  $_ = join(' ', luniq split(' ',$_));
}

##--------------------------------------------------------------
## set dbversion (extracted above as $dbstamp)
$rel{"dbversion:"} = $dbstamp;

##--------------------------------------------------------------
## dump
print STDERR "$0: dumping output to $outfile\n";
open(OUT,">$outfile")
  or die("$0: open failed for output file '$outfile': $!");
foreach (sort keys %rel) {
  print OUT $_, "\t", $rel{$_}, "\n";
}
close OUT;
