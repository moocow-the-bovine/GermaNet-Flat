#!/usr/bin/perl -w

use CGI qw(:standard :cgi-lib);
use lib qw(.);
use GermaNet::Flat;
use GraphViz;
use File::Basename qw(basename dirname);
use Encode qw(encode decode encode_utf8 decode_utf8);
use HTTP::Status;
use File::Temp;
use JSON;

use utf8;
use strict;
use open qw(:std :utf8);

##==============================================================================
## constants
our $prog = basename($0);

our $label   = "GermaNet"; ##-- top-level label
our $charset = 'utf-8'; ##-- this is all we support for now

our %defaults =
  (
   'q'=>'GNROOT',
   'f'=>'html',
   'case' => 1,
   'db' => 'gn',
  );

##-- local overrides
if (-r "$0.rc") {
  do "$0.rc";
  die("$0: error reading rc file $0.rc: $@") if ($@);
}

##==============================================================================
## utils

BEGIN {
  *htmlesc = \&escapeHTML;
}

my ($gn);
sub syn_label {
  my $syn = shift;
  return join("\\n", @{$gn->lex2orth($gn->syn2lex($syn))});
}

my (%nodes,%edges,$gv);
sub ensure_node {
  my ($syn,%opts) = @_;
  $gv->add_node(($nodes{$syn}=$syn),
		label=>syn_label($syn),
		URL=>"?s=$syn",
		%opts,
	       ) if (!exists $nodes{$syn});
}

sub ensure_edge {
  my ($from,$to,%opts) = @_;
  if (exists $edges{"$from $to"}) {
    print STDERR "edge exists: $from $to\n";
  }
  $edges{"$from $to"} = "$from $to";
  $gv->add_edge($from,$to,%opts);
  return;
}

sub synset_json {
  my $syn = shift;
  return {synset=>$syn, orth=>[map {s/_/ /g; $_} @{$gn->lex2orth($gn->syn2lex($syn))}]};
}

## $tmpdata = gvdump($gv,$fmt)
##  + workaround for broken UTF-8 support in GraphViz::as_* methods
sub gvdump {
  my ($gv,$fmt) = @_;
  my ($fh,$filename) = File::Temp::tempfile('gnvXXXXX',DIR=>'/tmp',SUFFIX=>".$fmt",UNLINK=>1);
  $fh->close();
  my $dot = $gv->as_debug;
  open(DOT,'|-','dot',"-T$fmt","-o$filename")
    or die("$prog: could not open pipe to dot: $!");
  binmode(DOT,':utf8');
  print DOT $dot
    or die("$prog: failed to write to DOT pipe: $!");
  close DOT
    or die("$prog: failed to close DOT pipe: $!");
  local $/=undef;
  open(BUF,"<:raw", $filename)
    or die("$prog: open failed for temp file '$filename': $!");
  my $buf = <BUF>;
  close BUF;

  return $buf;
}

## $bool = is_robot()
##  + check for common robots via user agent
##  + found in logs:
## "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
## "Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)" 
sub is_robot {
  my $ua = user_agent() // '';
  return $ua =~ /Googlebot|YandexBot/ ? 1 : 0;
}

##======================================================================
## cgi parameters

##-- DEBUG
sub showq {
  return;
  my ($lab,$q) = @_;
  $q //= '';
  printf STDERR
    ("$0: $lab: q=$q \[utf8:%d,valid:%d,check:%d]\n",
     (utf8::is_utf8($q) ? 1 : 0),
     (utf8::valid($q) ? 1 : 0),
     (Encode::is_utf8($q,1) ? 1 : 0),
    );
}

##-- get params
my $vars = {};
if (param()) {
  $vars = { Vars() }; ##-- copy tied Vars()-hash, otherwise utf8 flag gets handled wrong!
}

##-- rename vars
$vars->{q} //= (grep {$_} @$vars{qw(lemma l term t word w)})[0];
$vars->{s} //= (grep {$_} @$vars{qw(synset syn s)})[0];
$vars->{f} //= (grep {$_} @$vars{qw(format fmt f mode m)})[0];
$vars->{db} //= (grep {$_} @$vars{qw(database base db)})[0];
$vars->{case} //= (grep {$_} @$vars{qw(case_sensitive sensitive sens case cs)})[0];
showq('init', $vars->{q}//'');

charset($charset); ##-- initialize charset AFTER calling Vars(), otherwise fallback utf8::upgrade() won't work

##-- instantiate defaults
#use Data::Dumper; print STDERR Data::Dumper->Dump([\%defaults,$vars],['defaults','vars']);
$vars->{$_} = $defaults{$_} foreach (grep {!defined($vars->{$_})} keys %defaults);
showq('default', $vars->{q});

##-- sanitize vars
foreach (keys %$vars) {
  next if (!defined($vars->{$_}));
  my $tmp = $vars->{$_};
  $tmp =~ s/\x{0}//g;
  eval {
    ##-- try to decode utf8 params e.g. "%C3%B6de" for "öde"
    $tmp = decode_utf8($tmp,1) if (!utf8::is_utf8($tmp) && utf8::valid($tmp));
  };
  if ($@) {
    ##-- decoding failed; treat as bytes (e.g. "%F6de" for "öde")
    utf8::upgrade($tmp);
    undef $@;
  }
  $vars->{$_} = $tmp;
}

showq('sanitized', $vars->{q});

##==============================================================================
## MAIN
my %fmtxlate = ('text'=>'dot',
		'jpg'=>'jpeg',
	       );
my %fmt2type = ('png'=>'image/png',
		'gif'=>'image/gif',
		'jpeg'=>'image/jpeg',
		'dot'=>'text/plain',
		'canon'=>'text/plain',
		'debug'=>'text/plain',
		'cmapx'=>'text/plain',
		'imap'=>'text/html',
		'svg'=>'image/svg+xml',
		'json'=>'application/json',
	       );
eval {
  die "$prog: you must specify either a query term (q=TERM) or a synset (s=SYNSET)!"
    if (!$vars->{q} && !$vars->{s});

  my $dir0   = dirname($0);
  my $infile = (grep {-r "$dir0/$_"} map {($_,"$_.db")} map {($_,"${label}/$_")} ($vars->{db}))[0];
  die("$0: couldn't find input file for db=$vars->{db}") if (!$infile);
  $gn = GermaNet::Flat->load($infile)
    or die("$prog: failed to load '$infile': $!");

  ##-- output format
  my $fmt = $vars->{f};
  $fmt    = $fmtxlate{$fmt} if (exists($fmtxlate{$fmt}));

  ##-- basic properties
  my ($syns,$qtitle);
  if ($vars->{s}) {
    ##-- basic properties: synset query
    $syns   = [grep {exists($gn->{rel}{"syn2lex:$_"})} split(' ',$vars->{s})];
    $qtitle = '{'.join(', ', @{$gn->auniq($gn->synset_terms($syns))}).'}';
  } else {
    ##-- basic properties: lemma or synset query
    my @terms = split(' ',$vars->{q});
    @terms    = $gn->luniq(map {($_,lc($_),ucfirst(lc($_)))} @terms) if (!$vars->{case});
    $syns     = $gn->get_synsets(\@terms) // [];
    push(@$syns, grep {exists($gn->{rel}{"syn2lex:$_"})} @terms); ##-- allow synset names as 'lemma' queries
    $qtitle   = $vars->{q};
  }
  #print STDERR "syns = {", join(' ',@{$syns||[]}), "}\n";
  #die("$prog: no synset(s) found for query \`$qtitle'") if (!$syns || !@$syns);
  $syns //= [];

  ##-- header keys
  my %versionHeader = ("-X-germanet-version"=>($gn->dbversion()||'unknown'));

  if ($fmt eq 'json') {
    ##-- json format: just dump relations
    my $jdata = [];
    my ($jsyn);

    foreach my $syn (@$syns) {
      push(@$jdata, $jsyn=synset_json($syn));
      $jsyn->{hyperonyms}=[];
      $jsyn->{hyponyms}=[];

      foreach my $sup (@{$gn->hyperonyms($syn)}) {
	push(@{$jsyn->{hyperonyms}}, synset_json($sup));
      }
      foreach my $sub (@{$gn->hyponyms($syn)}) {
	push(@{$jsyn->{hyponyms}}, synset_json($sub));
      }
    }

    binmode *STDOUT, ':raw';
    print
      (header(-type=>$fmt2type{json},%versionHeader),
       to_json($jdata, {utf8=>1, pretty=>1, canonical=>1}),
      );

    exit 0;
  }


  ##-- graphviz object
  $gv = GraphViz->new(
		      directed=>1,
		      rankdir=>'LR',
		      #concentrate=>1,
		      name=>'gn',
		      node=>{shape=>'rectangle',fontname=>'arial',fontsize=>12,style=>'filled',fillcolor=>'white'},
		      edge=>{dir=>'back'},
		     );

  foreach my $syn (@$syns) {
    ensure_node($syn, fillcolor=>'yellow',fontname=>'arial bold',shape=>'circle');

    foreach my $sup (@{$gn->hyperonyms($syn)}) {
      ensure_node($sup, fillcolor=>'magenta');
      ensure_edge($sup, $syn);
    }
    foreach my $sub (@{$gn->hyponyms($syn)}) {
      ensure_node($sub, fillcolor=>'cyan');
      ensure_edge($syn, $sub);
    }
  }

  ##-- dump
  #print $gv->as_debug; exit 0;
  #print $gv->as_canon; exit 0;

  ##-- get content
  my ($fmtsub);
  if ($fmt eq 'html') {
    ##-- content: html
    my ($imgfmt);
    #$imgfmt = 'svg';
    $imgfmt = 'png';
    my $cmapx = gvdump($gv,'cmapx');
    if (1) {
      ##-- trim/rename titles
      $cmapx =~ s/\s(?:title|alt)=\"[^\"]*\"//sg;
      $cmapx =~ s/href=\"\?s=(\w+)\"/href="?s=$1" title="$1"/g;
    }
    print
      (header(-type=>'text/html',-charset=>$charset,%versionHeader),
       start_html("$label Graph: $qtitle"),
       h1("$label Graph: $qtitle"),
       ($syns && @$syns
	? ("<img src=\"${prog}?fmt=${imgfmt}&s=".join('+',@{$syns||[]})."\" usemap=\"#gn\" />\n",
	   $cmapx,
	  )
	: ("no synset(s) found!")
       ),
       end_html,
      );
  }
  elsif ($fmt eq 'debug') {
    print header(-type=>$fmt2type{$fmt},-charset=>'utf-8'), eval "\$gv->as_${fmt}()";
  }
  elsif (exists($fmt2type{$fmt})) {
    binmode *STDOUT, ':raw';
    print
      (header(-type=>($fmt2type{$fmt}//"application/octet-stream")),
       gvdump($gv,$fmt),
      );
  }
  else {
    die "$prog: unknown format '$fmt'";
  }
  exit 0;
};

##----------------------------------------------------------------------
## catch errors
if ($@) {
  print
    (header(-status=>RC_INTERNAL_SERVER_ERROR),
     start_html('Error'),
     h1('Error'),
     pre(escapeHTML($@)),
     end_html);
  exit 1;
}

