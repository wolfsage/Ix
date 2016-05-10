use v5.22.0;
package Test::DBMonster;
use Moose;

use experimental qw(postderef signatures);

use DBI;

has dsn      => (is => 'ro', default => 'dbi:Pg:');
has username => (is => 'ro', default => 'postgres');
has password => (is => 'ro', default => undef);
has basename => (is => 'ro', default => 'dbmonster');
has template => (is => 'ro', default => 'PID_T_N');

has master_dbh => (
  is      => 'ro',
  isa     => 'Object',
  lazy    => 1,
  default => sub ($self) {
    DBI->connect(
      $self->dsn,
      $self->username,
      $self->password,
      { RaiseError => 1 },
    );
  }
);

sub usernames ($self) {
  my $usernames = $self->master_dbh->selectcol_arrayref(
    'SELECT usename FROM pg_catalog.pg_user'
  );

  return grep { 0 == index $_, $self->basename } @$usernames;
}

sub databases ($self) {
  my $databases = $self->master_dbh->selectcol_arrayref(
    'SELECT datname FROM pg_catalog.pg_database'
  );

  return grep { 0 == index $_, $self->basename } @$databases;
}

my %EXPANDO = (PID => $$, T => $^T, N => sub { state $n; $n++ });

sub create_database ($self) {
  state $n;
  $n++;

  my @hunks = split /_/, $self->template;
  @hunks = map {; ref $EXPANDO{$_} ? $EXPANDO{$_}->()
                :     $EXPANDO{$_} ? $EXPANDO{$_}
                :                    $_               } @hunks;

  my $name = join q{_}, $self->basename, @hunks;

  $self->master_dbh->do("CREATE USER $name WITH PASSWORD '$name'");

  $self->master_dbh->do("CREATE DATABASE $name WITH OWNER $name");

  return (
    $self->dsn . "dbname=$name",
    $name,
    $name,
  );
}

sub clean_house ($self) {
  my $master_dbh = $self->master_dbh;
  for my $database ($self->databases) {
    $master_dbh->do("DROP DATABASE $database");
  }

  for my $username ($self->usernames) {
    $master_dbh->do("DROP USER $username");
  }

  return;
}

1;
