package Mojo::MySQL5;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::MySQL5::Migrations;
use Mojo::MySQL5::URL;
use Mojo::MySQL5::Database;
use Mojo::Util 'deprecated';
use Scalar::Util 'weaken';

has max_connections => 5;
has migrations      => sub {
  my $migrations = Mojo::MySQL5::Migrations->new(mysql => shift);
  weaken $migrations->{mysql};
  return $migrations;
};
has url             => sub { Mojo::MySQL5::URL->new('mysql:///test') };

our $VERSION = '0.01';

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  my $c = $self->_dequeue;
  my $db = Mojo::MySQL5::Database->new(connection => $c, mysql => $self);

  if (!$c) {
    $db->connect($self->url);
    $self->emit(connection => $db);
  }
  return $db;
}

sub from_string {
  my ($self, $str) = @_;
  my $url = Mojo::MySQL5::URL->new($str);
  croak qq{Invalid MySQL connection string "$str"} unless $url->protocol eq 'mysql';

  return $self->url($url);
}

sub new { @_ > 1 ? shift->SUPER::new->from_string(@_) : shift->SUPER::new }

sub _dequeue {
  my $self = shift;

  while (my $c = shift @{$self->{queue} || []}) { return $c if $c->ping }
  return undef;
}

sub _enqueue {
  my ($self, $c) = @_;
  my $queue = $self->{queue} ||= [];
  push @$queue, $c;
  shift @{$self->{queue}} while @{$self->{queue}} > $self->max_connections;
}

# deprecated attributes

sub password {
  my $self = shift;
  return $self->url->password unless @_;
  $self->url->password(@_);
  return $self;
}

sub username {
  my $self = shift;
  return $self->url->username unless @_;
  $self->url->username(@_);
  return $self;
}

sub options {
  my $self = shift;
  return $self->url->options unless @_;
  $self->url->options(@_);
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::MySQL5 - Pure-Perl non-blocking I/O MySQL Connector

=head1 SYNOPSIS

  use Mojo::MySQL5;

  # Create a table
  my $mysql = Mojo::MySQL5->new('mysql://username@/test');
  $mysql->db->query('create table names (id integer auto_increment primary key, name text)');

  # Insert a few rows
  my $db = $mysql->db;
  $db->query('insert into names (name) values (?)', 'Sara');
  $db->query('insert into names (name) values (?)', 'Stefan');

  # Insert more rows in a transaction
  {
    my $tx = $db->begin;
    $db->query('insert into names (name) values (?)', 'Baerbel');
    $db->query('insert into names (name) values (?)', 'Wolfgang');
    $tx->commit;
  };

  # Insert another row and return the generated id
  say $db->query('insert into names (name) values (?)', 'Daniel')
    ->last_insert_id;

  # Select one row at a time
  my $results = $db->query('select * from names');
  while (my $next = $results->hash) {
    say $next->{name};
  }

  # Select all rows blocking
  $db->query('select * from names')
    ->hashes->map(sub { $_->{name} })->join("\n")->say;

  # Select all rows non-blocking
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      $db->query('select * from names' => $delay->begin);
    },
    sub {
      my ($delay, $err, $results) = @_;
      $results->hashes->map(sub { $_->{name} })->join("\n")->say;
    }
  )->wait;

=head1 DESCRIPTION

L<Mojo::MySQL5> makes L<MySQL|http://www.mysql.org> a lot of fun to use with the
L<Mojolicious|http://mojolicio.us> real-time web framework.

Database handles are cached automatically, so they can be reused transparently
to increase performance. And you can handle connection timeouts gracefully by
holding on to them only for short amounts of time.

  use Mojolicious::Lite;
  use Mojo::MySQL5;

  helper mysql =>
    sub { state $mysql = Mojo::MySQL5->new('mysql://sri:s3cret@localhost/db') };

  get '/' => sub {
    my $c  = shift;
    my $db = $c->mysql->db;
    $c->render(json => $db->query('select now() as time')->hash);
  };

  app->start;

This module implements two methods of connecting to MySQL server.

=over 2

=item Using DBI and DBD::MySQL5

L<DBD::MySQL5> allows you to submit a long-running query to the server
and have an event loop inform you when it's ready. 

While all I/O operations are performed blocking,
you can wait for long running queries asynchronously, allowing the
L<Mojo::IOLoop> event loop to perform other tasks in the meantime. Since
database connections usually have a very low latency, this often results in
very good performance.

=item Using Native Pure-Perl Non-Blocking I/O

L<Mojo::MySQL5::Connection> is Fully asynchronous implementation
of MySQL Client Server Protocol managed by L<Mojo::IOLoop>.

This method is EXPERIMENTAL.

=back

Every database connection can only handle one active query at a time, this
includes asynchronous ones. So if you start more than one, they will be put on
a waiting list and performed sequentially. To perform multiple queries
concurrently, you have to use multiple connections.
 
  # Performed sequentially (10 seconds)
  my $db = $mysql->db;
  $db->query('select sleep(5)' => sub {...});
  $db->query('select sleep(5)' => sub {...});
 
  # Performed concurrently (5 seconds)
  $mysql->db->query('select sleep(5)' => sub {...});
  $mysql->db->query('select sleep(5)' => sub {...});
 
All cached database handles will be reset automatically if a new process has
been forked, this allows multiple processes to share the same L<Mojo::MySQL5>
object safely.


Note that this whole distribution is EXPERIMENTAL and will change without
warning!

=head1 EVENTS

L<Mojo::MySQL5> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 connection

  $mysql->on(connection => sub {
    my ($mysql, $db) = @_;
    ...
  });

Emitted when a new database connection has been established.

=head1 ATTRIBUTES

L<Mojo::MySQL5> implements the following attributes.

=head2 dsn

  my $dsn = $mysql->dsn;
  $mysql  = $mysql->dsn('dbi:mysql:dbname=foo');

Data Source Name.

This attribute is DEPRECATED and is L<DBI> specific. Use L<url|"/url">->dsn istead.

=head2 max_connections

  my $max = $mysql->max_connections;
  $mysql  = $mysql->max_connections(3);

Maximum number of idle database handles to cache for future use, defaults to
C<5>.

=head2 migrations

MySQL does not support nested transactions and DDL transactions.
DDL statements cause implicit C<COMMIT>.
B<Therefore, migrations should be used with extreme caution.
Backup your database. You've been warned.> 

  my $migrations = $mysql->migrations;
  $mysql         = $mysql->migrations(Mojo::MySQL5::Migrations->new);

L<Mojo::MySQL5::Migrations> object you can use to change your database schema more
easily.

  # Load migrations from file and migrate to latest version
  $mysql->migrations->from_file('/home/sri/migrations.sql')->migrate;

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({found_rows => 0, PrintError => 1});

Options for connecting to server.

This attribute is DEPRECATED. Use L<url|"/url">->options istead.

=head2 password

  my $password = $mysql->password;
  $mysql       = $mysql->password('s3cret');

Database password, defaults to an empty string.

This attribute is DEPRECATED. Use L<url|"/url">->password istead.

=head2 username

  my $username = $mysql->username;
  $mysql       = $mysql->username('batman');

Database username, defaults to an empty string.

This attribute is DEPRECATED. Use L<url|"/url">->username istead.

=head2 url

  my $url = $mysql->url;
  $url  = $mysql->url(Mojo::MySQL5::URL->new('mysql://user@host/test?PrintError=0'));

Connection L<URL|Mojo::MySQL5::URL>.

Supported URL Options are:

=over 2

=item use_dbi

Use L<DBI|DBI> and L<DBD::MySQL5> when enabled or not specified.
Native implementation when disabled.

=item found_rows

Enables or disables the flag C<CLIENT_FOUND_ROWS> while connecting to the server.
Without C<found_rows>, if you perform a query like
 
  UPDATE $table SET id = 1 WHERE id = 1;
 
then the MySQL engine will return 0, because no rows have changed.
With C<found_rows>, it will return the number of rows that have an id 1.

=item multi_statements

Enables or disables the flag C<CLIENT_MULTI_STATEMENTS> while connecting to the server.
If enabled multiple statements separated by semicolon (;) can be send with single
call to $db->L<query|Mojo::MySQL5::Database/"query">.

=item utf8

Set default character set to C<utf-8> while connecting to the server
and decode correctly utf-8 text results.

=item connect_timeout

The connect request to the server will timeout if it has not been successful
after the given number of seconds.

=item query_timeout

If enabled, the read or write operation to the server will timeout
if it has not been successful after the given number of seconds.

=item PrintError

C<warn> on errors.

=back

Default Options are:

C<utf8 = 1>,
C<found_rows = 1>,
C<PrintError = 0>

When using DBI method, driver private options (prefixed with C<mysql_>) of L<DBD::MySQL5> are supported.

C<mysql_auto_reconnect> is never enabled, L<Mojo::MySQL5> takes care of dead connections.

C<AutoCommit> cannot not be disabled, use $db->L<begin|Mojo::MySQL5::Database/"begin"> to manage transactions.

C<RaiseError> is always enabled for blocking and disabled non-blocking queries.

=head1 METHODS

L<Mojo::MySQL5> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 db

  my $db = $mysql->db;

Get L<Mojo::MySQL5::Database> object for a cached or newly created database
handle. The database handle will be automatically cached again when that
object is destroyed, so you can handle connection timeouts gracefully by
holding on to it only for short amounts of time.

  # Add up all the money
  say $mysql->db->query('select * from accounts')
    ->hashes->reduce(sub { $a->{money} + $b->{money} });

=head2 from_string

  $mysql = $mysql->from_string('mysql://user@/test');

Parse configuration from connection string.

  # Just a database
  $mysql->from_string('mysql:///db1');

  # Username and database
  $mysql->from_string('mysql://batman@/db2');

  # Username, password, host and database
  $mysql->from_string('mysql://batman:s3cret@localhost/db3');

  # Username, domain socket and database
  $mysql->from_string('mysql://batman@%2ftmp%2fmysql.sock/db4');

  # Username, database and additional options
  $mysql->from_string('mysql://batman@/db5?PrintError=1');

=head2 new

  my $mysql = Mojo::MySQL5->new;
  my $mysql = Mojo::MySQL5->new('mysql://user:password@host:port/database');

Construct a new L<Mojo::MySQL5> object and parse connection string with
L</"from_string"> if necessary.

=head1 REFERENCE

This is the class hierarchy of the L<Mojo::MySQL5> distribution.

=over 2

=item * L<Mojo::MySQL5>

=item * L<Mojo::MySQL5::Connection>

=item * L<Mojo::MySQL5::Database>

=item * L<Mojo::MySQL5::Migrations>

=item * L<Mojo::MySQL5::Results>

=item * L<Mojo::MySQL5::Transaction>

=item * L<Mojo::MySQL5::URL>

=item * L<Mojo::MySQL5::Util>

=back

=head1 AUTHOR

Curt Hochwender, C<hochwender@centurytel.net>.

Jan Henning Thorsen, C<jhthorsen@cpan.org>.

This code is mostly a rip-off from Sebastian Riedel's L<Mojo::Pg>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2015, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Pg>, L<https://github.com/jhthorsen/mojo-mysql>,
L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
