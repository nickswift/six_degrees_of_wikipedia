#!/usr/bin/perl
use strict;
use warnings;

use Storable;

my $regex_tag   = qr/(<a href="\/wiki\/([A-z0-9()\/\:]+)"[^>]*>([^<>]*)<\/a>)/;
my $total_links = 0;
my $first_open  = 0;

sub get_wikifile ($)
{
  my $wikifile = 'wikifiles/'.shift.'.wiki';
  $first_open  = -r $wikifile ? 0 : 1;

  store({}, $wikifile) unless -r $wikifile;
  my $hash = retrieve($wikifile);
  return $hash;
}

sub store_wikifile ($$)
{
  my $hash     = shift;
  my $wikifile = 'wikifiles/'.shift.'.wiki';
  store($hash, $wikifile);
}

# retrieve article from wikipedia
sub get_article ($$)
{
  my ($article, $terms) = @_;
  my $contents = `curl -s "http://en.wikipedia.org/wiki/$article"`;

  # Extract tags
  while ($contents =~ m/${$regex_tag}/g) {
    # skip over articles
    my $term = $2;

    # skip anything with just numbers and/or nonchars
    next if ($term =~ m/^((\d+)|([^\w]+))+$/);
    # skip any number longer than a year
    next if ($term =~ m/\d\d\d\d\d+/);
    # skip over articles with a colon
    next if ($term =~ m/\:/);
    # skip over lists
    next if ($term =~ m/List_.+/);
    # skip over ISBN entry
    next if ($term =~ m/International_Standard_Book_Number/);

    # add article
    if (!exists($terms->{$term})) {
      # create the node
      $terms->{$term} = {
        'source'   => $article, 
        'article'  => $2,
        'searched' => 0,
        'links'    => 0
      };
    } else {
      # add to number of links
      $terms->{$term}->{'links'}++;
      $total_links++;
    }
  }
}

# main subroutine
sub main ($$)
{
  my ($start, $end) = @_;
  my %terms         = %{get_wikifile($start)};
  my $pagerank;
  my $firstpass     = 1;

  print("PROBING: $start --> $end\n");
  get_article($start, \%terms);

  print(keys(%terms)." entries\n");

  while (!exists($terms{$end})) {
    print("RE-RANK PAGES\n");
    # pagerank all entries
    $pagerank = {};
    map {
      my $links = $terms{$_}->{'links'};
      $pagerank->{$links} = () if (!exists($pagerank->{$links}));
      # only push the page if it's still unchecked
      push(@{$pagerank->{$links}}, $terms{$_}) if($terms{$_}->{'searched'} == 0);
    } keys(%terms);

    my $ksize = int(keys(%{$pagerank}));
    my $kstop = $ksize - $ksize/10;

    # Step backwards through pagerank obtaining links
    foreach my $ka (sort { $b <=> $a } keys(%{$pagerank})) {

      if ($total_links > $kstop && ($firstpass == 0 || $first_open == 0)) {
        $total_links = 0;
        last;
      }

      # skip empty buckets
      next if ($ka == 0);
      foreach my $kb (@{$pagerank->{$ka}}) {
        printf("%50s CURRENT RANK: %-10s\n", $kb->{'article'}, $kb->{'links'});
        get_article($kb->{'article'}, \%terms);
        $kb->{'searched'} = 1;
        last if(exists($terms{$end}));
      }
      last if(exists($terms{$end}));
    }

    $firstpass = 0;

    # store the current hashfile
  store_wikifile(\%terms, $start);
  }

  my $article = $terms{$end}->{'article'};
  my $source  = $terms{$end}->{'source'};

  print("\n    RESULT: $article --> ");
  my $degrees = 0;
  while ($source ne $start) {
    $degrees++;
    print("($source) --> ");
    $end    = $source;
    $source = $terms{$end}->{'source'};
  }
  print("$start\n    $degrees DEGREES OF SEPARATION\n");

  # store the current hashfile
  store_wikifile(\%terms, $start);
}

main($ARGV[0], $ARGV[1]);