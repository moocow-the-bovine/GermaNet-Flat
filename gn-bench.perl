#!/usr/bin/perl -w

use lib qw(.);
use GermaNet::GermaNet;
use GermaNet::LexUnit;
use GermaNet::Flat;
use File::Basename qw(basename);
use Storable;
use Benchmark qw(cmpthese timethese);

use open qw(:std :utf8);

##==============================================================================
## constants
our $prog = basename($0);

##==============================================================================
## command-line
our ($gnafile,$flatfile,@terms) = @ARGV;
foreach (@terms) { utf8::decode($_) if (!utf8::is_utf8($_)); }
die("Usage: $prog GNAFILE FLATFILE TERM(s)\n") if (@ARGV < 3);

##==============================================================================
## bench

##---------------------------------------------------------------
## bench: utils

## @terms = gna_synset_terms($gna, $synset)
sub gna_synset_terms {
  return map {s/\s/_/g; $_} map {@{$_->get_orth_forms}} @{$_[1]->get_lex_units};
}

##---------------------------------------------------------------
## \@synterms = gna_syns1($gn, @terms)
sub gna_syns1 {
  my $gna = shift;
  my ($syns,@syns);
  foreach (@_) {
    $syns = $gna->get_synsets($_) || next;
    push(@syns,
	 map {
	   map {defined($_) ? gna_synset_terms($gna,$_) : qw()}
	   ($_,
	    @{$_->get_relations('hyperonymy')},
	    @{$_->get_relations('hyponymy')},
	   )
	 } @$syns);
  }
  return GermaNet::Flat::auniq \@syns;
}

##---------------------------------------------------------------
## \@synterms = flat_syns1($gn, @terms)
sub flat_syns1 {
  my $gnf = shift;
  my $syns = $gnf->get_synsets(\@_) || return [];
  push(@$syns,
       @{$gnf->relation('hyperonymy',$syns)},
       @{$gnf->relation('hyponymy',$syns)});
  return $gnf->auniq($gnf->synset_terms($syns));
}

##==============================================================================
## MAIN

print STDERR "$prog: loading...";

##-- load GermaNet::GermaNet (Holger Wunsch API) data
my ($gna);
if ($gnafile ne '') {
  $gna = Storable::retrieve($gnafile)
    or die("$prog: failed to load GermaNet::GermaNet data from '$gnafile': $!");
}

##-- load flat data
my $gnf = GermaNet::Flat->load($flatfile)
  or die("$prog: failed to load flat data from '$flatfile': $!");
my $flatmode = $gnf->{inmode};

##-- load db if available
my ($gndb);
if ($flatmode ne 'db') {
  (my $dbfile=$flatfile)=~s/\.[^\.]*$/\.db/;
  $gndb = GermaNet::Flat->loadDB($dbfile) if (-r $dbfile);
}
##-- load cdb if available
my ($gncdb);
if ($flatmode ne 'cdb') {
  (my $dbfile=$flatfile)=~s/\.[^\.]*$/\.cdb/;
  $gncdb = GermaNet::Flat->loadCDB($dbfile) if (-r $dbfile);
}

print STDERR " loaded.\n";

##-- DEBUG
my $terms     = join(' ', @terms);
my $gna_syns1 = $gna ? gna_syns1($gna, @terms) : undef;
my $gnf_syns1 = $gnf ? flat_syns1($gnf, @terms) : undef;
my $gndb_syns1 = $gndb ? flat_syns1($gndb, @terms) : undef;
my $gncdb_syns1 = $gndb ? flat_syns1($gncdb, @terms) : undef;
print STDERR
  ("> API file: $gnafile\n",
   "> Flat file [$flatmode]: $flatfile\n",
   "> term(s) = $terms\n",
   "> API    syns = ", join(' ',@{$gna_syns1||[]}), "\n",
   "> Flat   syns = ", join(' ',@{$gnf_syns1||[]}), "\n",
   ($gndb ? ("> FlatDB syns = ", join(' ',@{$gndb_syns1||[]}), "\n") : qw()),
   ($gncdb ? (">    CDB syns = ", join(' ',@{$gncdb_syns1||[]}), "\n") : qw()),
 );
#exit 0;

##-- BENCH
cmpthese(-3,
	 {
	  ($gna ? (api=>sub {gna_syns1($gna,@terms)}) : qw()),
	  ($gnf ? ("flat/$flatmode"=>sub {flat_syns1($gnf,@terms)}) : qw()),
	  ($gndb ? ("flat/db"=>sub {flat_syns1($gndb,@terms)}) : qw()),
	  ($gncdb ? ("flat/cdb"=>sub {flat_syns1($gncdb,@terms)}) : qw()),
	 });
