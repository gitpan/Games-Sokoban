=head1 NAME

Games::Sokoban - load/transform/save sokoban levels in various formats

=head1 SYNOPSIS

 use Games::Sokoban;

=head1 DESCRIPTION

I needed something like this quickly - if you need better docs, you have to ask.

Supports xsb (text), rle, sokevo and a small "binpack" format for input
and output and can normalise levels as well as calculate unique IDs.

=over 4

=cut

package Games::Sokoban;

use common::sense;

use Carp ();
use List::Util ();

our $VERSION = '0.02';

=item $level = new Games::Sokoban [format => "text|binpack"], [data => "###..."]

=cut

sub new {
   my ($class, %arg) = @_;

   my $self = bless \%arg, $class;

   $self->data (delete $self->{data}, delete $self->{format})
      if exists $self->{data};

   $self
}

=item $level = new_from_file Games::Sokoban $path[, $format]

=cut

sub new_from_file {
   my ($class, $path, $format) = @_;

   open my $fh, "<:perlio", $path
      or Carp::croak "$path: $!";
   local $/;

   $class->new (data => (scalar <$fh>), format => $format)
}

sub detect_format($) {
   my ($data) = @_;

   return "text" if $data =~ /^[ #\@\*\$\.\+\015\012\-_]+$/;

   warn $data;#d#
   return "rle"  if $data =~ /^[ #\@\*\$\.\+\015\012\-_|1-9]+$/;
   exit 5;#d#

   my ($a, $b) = unpack "ww", $data;
   return "binpack" if defined $a && defined $b;

   Carp::croak "unable to autodetect sokoban level format";
}

=item $level->data ([$new_data, [$new_data_format]]])

=cut

sub data {
   my ($self, $data, $format) = @_;

   $format ||= detect_format $data;

   if ($format eq "text" or $format eq "rle") {
      $data =~ y/-_|/  \n/;
      $data =~ s/(\d)(.)/$2 x $1/ge;
      my @lines = split /[\015\012]+/, $data;
      my $w = List::Util::max map length, @lines;

      $_ .= " " x ($w - length)
         for @lines;

      $self->{data} = join "\n", @lines;

   } elsif ($format eq "binpack") {
      (my ($w, $s), $data) = unpack "wwB*", $data;

      my @enc = ('#', '$', '.', '   ', ' ', '###', '*', '# ');

      $data = join "",
              map $enc[$_],
              unpack "C*",
              pack "(b*)*",
              unpack "(a3)*", $data;

      # clip extra chars (max. 2)
      my $extra = (length $data) % $w;
      substr $data, -$extra, $extra, "" if $extra;

      (substr $data, $s, 1) =~ y/ ./@+/;

      $self->{data} =
        join "\n",
        map "#$_#",
            "#" x $w,
            (unpack "(a$w)*", $data),
            "#" x $w;
        
   } else {
      Carp::croak "$format: unsupported sokoban level format requested";
   }

   $self->update;

   ($self->{data})
}

sub pos2xy {
   use integer;

   $_[1] >= 0
      or Carp::croak "illegal buffer offset";

   (
      $_[1] % ($_[0]{w} + 1),
      $_[1] / ($_[0]{w} + 1),
   )
}

sub update {
   my ($self) = @_;

   for ($self->{data}) {
      s/^\n+//;
      s/\n$//;

      /^[^\n]+/ or die;

      $self->{w} = index $_, "\n";
      $self->{h} = y/\n// + 1;
   }
}

=item $text = $level->as_text

=cut

sub as_text {
   my ($self) = @_;

   "$self->{data}\n"
}

=item $binary = $level->as_binpack

=cut

sub as_binpack {
   my ($self) = @_;

   my $binpack = chr $self->{w} - 2;

   my $w = $self->{w};

   my $data = $self->{data};

   # crop away all four borders
   $data =~ s/^#+\n//;
   $data =~ s/#+$//;
   $data =~ s/#$//mg;
   $data =~ s/^#//mg;

   $data =~ y/\n//d;

   $data =~ /[\@\+]/ or die;
   my $s = $-[0];
   (substr $data, $s, 1) =~ y/@+/ ./;

   $data =~ s/\#\#\#/101/g;
   $data =~ s/\ \ \ /110/g;
   $data =~ s/\#\ /111/g;

   $data =~ s/\#/000/g;
   $data =~ s/\ /001/g;
   $data =~ s/\./010/g;
   $data =~ s/\*/011/g;
   $data =~ s/\$/100/g;

   # width, @-offset, data

   pack "wwB*", $w - 2, $s, $data
}

=item @lines = $level->as_lines

=cut

sub as_lines {
   split /\n/, $_[0]{data}
}

=item @lines = $level->as_rle

http://www.sokobano.de/wiki/index.php?title=Level_format

=cut

sub as_rle {
   my $data = $_[0]{data};

   $data =~ s/ +$//mg;
   $data =~ y/\n /|-/;
   $data =~ s/((.)\2{2,8})/(length $1) . $2/ge;

   $data
}

=item ($x, $y) = $level->start

=cut

sub start {
   my ($self) = @_;

   $self->{data} =~ /[\@\+]/ or Carp::croak "level has no starting point";
   $self->pos2xy ($-[0]);
}

=item $level->hflip

=item $level->vflip

=item $level->transpose # topleft to bottomright

=item $level->rotate_90

=item $level->rotate_180

=cut

sub hflip {
   $_[0]{data} = join "\n", map { scalar reverse $_ } split /\n/, $_[0]{data};
}

sub vflip {
   $_[0]{data} = join "\n", reverse split /\n/, $_[0]{data};
}

sub transpose {
   my ($self) = @_;

   # there must be a more elegant way :/
   my @c;

   for (split /\n/, $self->{data}) {
      my $i;

      $c[$i++] .= $_ for split //;
   }

   $self->{data} = join "\n", @c;
   ($self->{w}, $self->{h}) = ($self->{h}, $self->{w})
}

sub rotate_90 {
   $_[0]->vflip;
   $_[0]->transpose;
}

sub rotate_180 {
   $_[0]{data} = reverse $_[0]{data};
}

=item $id = $level->simplify

Detect playable area, crop to smallest size.

=cut

sub simplify {
   my ($self) = @_;

   # first detect playable area
   my ($w, $h) = ($self->{w}, $self->{h});
   my ($x, $y) = $self->start;

   my @data = split /\n/, $self->{data};
   my @mask = @data;

   y/#/\x00/c, y/#/\x7f/ for @mask;

   my @stack = [$x, $y, 0];

   while (@stack) {
      my ($x, $y, $l) = @{ pop @stack };
      my $line = $mask[$y];

      for my $x ($x .. $x + $l) {
         (reverse substr $line, 0, $x + 1) =~ /\x00+/
            or next;

         $l = $+[0];

         $x -= $l - 1;
         (substr $line, $x) =~ /^\x00+/ or die;
         $l = $+[0];

         substr $mask[$y], $x, $l, "\xff" x $l;

         push @stack, [$x, $y - 1, $l - 1] if $y > 0;
         push @stack, [$x, $y + 1, $l - 1] if $y < $h - 1;
      }
   }

   my $walls = "#" x $w;

   for (0 .. $h - 1) {
      $data[$_] = ($data[$_] & $mask[$_]) | ($walls & ~$mask[$_]);
   }

   # reduce borders
   pop   @data while @data > 2 && $data[-2] eq $walls; # bottom
   shift @data while $data[1] eq $walls; # top

   for ($self->{data} = join "\n", @data) {
      s/#$//mg until /[^#]#$/m; # right
      s/^#//mg until /^#[^#]/m; # left
   }

   # phew, done
}

=item $id = $level->normalise

normalises the level map and calculates/returns it's identity code

http://www.sourcecode.se/sokoban/level_id.php, assume uppercase and hex.

=cut

sub normalise {
   my ($self) = @_;

   $self->simplify;

   require Digest::MD5;

   my ($best_md5, $best_data) = "\xff" x 9;

   my $chk = sub {
      my $md5 = substr Digest::MD5::md5 ("$self->{data}\n"), 0, 8;
      if ($md5 lt $best_md5) {
         $best_md5  = $md5;
         $best_data = $self->{data};
      }
   };

   $chk->(); $self->hflip;
   $chk->(); $self->vflip;
   $chk->(); $self->hflip;
   $chk->(); $self->rotate_90;
   $chk->(); $self->hflip;
   $chk->(); $self->vflip;
   $chk->(); $self->hflip;
   $chk->();

   $self->data ($best_data, "text");

   uc unpack "H*", $best_md5
}

=item $levels = Games::Sokoban::load_sokevo $path

Loads a sokevo snapshot/history file and returns all contained levels as
Games::Sokoban objects in an arrayref.

=cut

sub load_sokevo($) {
   open my $fh, "<", $_[0]
      or Carp::croak "$_[0]: $!";

   my @levels;

   while (<$fh>) {
      if (/^##+$/) {
         my $data = $_;
         while (<$fh>) {
            $data .= $_;
            last if /^$/;
         }

         push @levels, new Games::Sokoban data => $data;
      }
   }

   \@levels
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

