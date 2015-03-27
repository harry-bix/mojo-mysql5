package Mojo::MySQL5::Util;
use Mojo::Base -strict;

use Mojo::URL;
use Exporter 'import';

our @EXPORT_OK = qw(flag_list flag_set flag_is quote quote_id);

# Flag functions

sub flag_list($$;$) {
  my ($list, $data, $sep) = @_;
  my $i = 0;
  return join $sep || '|', grep { $data & 1 << $i++ } @$list;
}

sub flag_set($;@) {
  my ($list, @ops) = @_;
  my ($i, $flags) = (0, 0);
  foreach my $flag (@$list) {
    do { $flags |= 1 << $i if $_ eq $flag } for @ops; 
    $i++;
  }
  return $flags;
}

sub flag_is($$$) {
  my ($list, $data, $flag) = @_;
  my $i = 0;
  foreach (@$list) {
    return $data & 1 << $i if $flag eq $_;
    $i++;
  }
  return undef;
}

sub quote {
  my $string = shift;
  return 'NULL' unless defined $string;

  for ($string) {
    s/\\/\\\\/g;
    s/\0/\\0/g;
    s/\n/\\n/g;
    s/\r/\\r/g;
    s/'/\\'/g;
    # s/"/\\"/g;
    s/\x1a/\\Z/g;
  }

  return "'$string'";
}

sub quote_id {
  my $id = shift;
  return 'NULL' unless defined $id;
  $id =~ s/`/``/g;
  return "`$id`";
}

1;

=encoding utf8
 
=head1 NAME
 
Mojo::MySQL5::Util - Utility functions
 
=head1 SYNOPSIS
 
  use Mojo::MySQL5::Util qw(quote quote_id);
 
  my $str = "I'm happy\n";
  my $escaped = quote $str;
 
=head1 DESCRIPTION
 
L<Mojo::MySQL5::Util> provides utility functions for L<Mojo::MySQL5>.
 
=head1 FUNCTIONS
 
L<Mojo::MySQL5::Util> implements the following functions, which can be imported
individually.
 
=head2 expand_sql
 
  my $sql = expand_sql("select name from table where id=?", $id);
 
Replace ? in SQL query with quoted arguments.

=head2 flag_list \@names, $int, $separator

  say flag_list(['one' 'two' 'three'], 3, ',');   # one,two
  say flag_list(['one' 'two' 'three'], 4, ',');   # three
  say flag_list(['one' 'two' 'three'], 6);        # one|two|three

List bit flags that are set in integer.

=head2 flag_set \@names, @flags

  say flag_set(['one' 'two' 'three'], 'one', 'two');  # 3
  say flag_set(['one' 'two' 'three'])                 # 0

Set named bit flags.

=head2 flag_is \@names, $int, $flag

  say flag_is(['one' 'two' 'three'], 1, 'one');     # true
  say flag_is(['one' 'two' 'three'], 3, 'two');     # true
  say flag_is(['one' 'two' 'three'], 3, 'three');   # false

Check if named bit flag is set.

=head2 quote
 
  my $escaped = quote $str;
 
Quote string value for passing to SQL query.
 
=head2 quote_id
 
  my $escaped = quote_id $id;
 
Quote identifier for passing to SQL query.

=cut
