use strict;
use warnings;
use experimental qw(postderef signatures);
package Bakesale::Schema::Result::User;
use base qw/DBIx::Class::Core/;

use Ix::Validators qw(enum);

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

__PACKAGE__->table('users');

__PACKAGE__->ix_add_columns;

__PACKAGE__->ix_add_properties(
  username    => { data_type => 'text' },
  status      => { data_type => 'text', validator => enum([ qw(active okay) ]) },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->add_unique_constraint(
  [ qw(username) ],
);

sub ix_type_key { 'users' }

sub ix_default_properties ($self, $ctx) {
  return {
    status => 'active',
  },
}

sub ix_create_error ($self, $ctx, $error) {
  if ($error =~ /duplicate key value/) {
    return $ctx->error(alreadyExists => {
      description => "that username already exists during create",
    });
  }

  return;
}

sub ix_update_error ($self, $ctx, $error) {
  if ($error =~ /duplicate key value/) {
    return $ctx->error(alreadyExists => {
      description => "that username already exists during update",
    });
  }

  return;
}

sub ix_create_check ($self, $ctx, $arg) {
  # Super contrived test - change 'okay' to 'active', used to make sure
  # behind-the-scenes changes during create bubble up to the response
  # seen by the caller
  if ($arg->{status} && $arg->{status} eq 'okay') {
    $arg->{status} = 'active';
  }

  return;
}

1;
