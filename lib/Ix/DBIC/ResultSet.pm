use 5.20.0;
use warnings;
package Ix::DBIC::ResultSet;
use parent 'DBIx::Class::ResultSet';

use experimental qw(signatures postderef);

use Ix::Util qw(error);
use Safe::Isa;

use namespace::clean;

sub _ix_rclass ($self) {
  my $rclass = $self->result_source->result_class;

  # TODO: make this check something non-garbagey
  Carp::confess("ix_create called with non-Ix-compatible result class: $rclass")
    unless $rclass->isa('Ix::DBIC::Result');

  return $rclass;
}

sub ix_create ($self, $to_create, $ephemera) {
  my $account_id = $Bakesale::Context::Context->account_id;

  my $rclass = $self->_ix_rclass;

  my $type_key = $rclass->ix_type_key;

  # XXX: this is garbage, fix it -- rjbs, 2016-02-18
  my $next_state = $ephemera->{next_state}{$type_key};

  # TODO handle unknown properties
  my $error = error('invalidRecord', { description => "could not update" });

  my %result;

  my $now = time; # pull off of context? -- rjbs, 2016-02-18

  my @user_props = $rclass->ix_user_property_names;

  for my $id (keys $to_create->%*) {
    my %rec = (
      # barf if there are unexpected properties, don't just drop them
      # -- rjbs, 2016-02-18
      (@user_props ? $to_create->{$id}->%{@user_props} : ()),

      # XXX: this surely must require a lot more customizability; pass in
      # context, user props, blah blah blah
      $rclass->ix_default_properties->%*,

      account_id => $account_id,
      state      => $next_state,
    );

    my $row = eval { $self->create(\%rec); };

    if ($row) {
      # This is silly.  Can we get a pair slice out of a Row?
      $result{created}{$id} = { id => $row->id, %rec{qw(baked_at)} };

      $ephemera->{$type_key}{$id} = $row->id;
    } else {
      $result{not_created}{$id} = $error;
    }
  }

  return \%result;
}

sub ix_update ($self, $to_update, $ephemera) {
  my $account_id = $Bakesale::Context::Context->account_id;

  my $rclass = $self->_ix_rclass;

  my %result;

  my @updated;
  my $error = error('invalidRecord', { description => "could not update" });
  for my $id (keys $to_update->%*) {
    my $row = $self->find({ id => $id, account_id => $account_id });

    # TODO: validate the update -- rjbs, 2016-02-16
    my $ok = eval { $row->update($to_update->{$id}); 1 };

    if ($ok) {
      push @updated, $id;
    } else {
      $result{not_updated}{$id} = $error;
    }
  }

  $result{updated} = \@updated;

  return \%result;
}

sub ix_destroy ($self, $to_destroy, $ephemera) {
  my $account_id = $Bakesale::Context::Context->account_id;

  my $rclass = $self->_ix_rclass;

  my %result;

  my @destroyed;
  for my $id ($to_destroy->@*) {
    my $rv = $self->search({ id => $id, account_id => $account_id })
                  ->delete;

    if ($rv > 0) {
      push @destroyed, $id;
    } else {
      $result{not_destroyed}{$id} = error('failedToDelete');
    }
  }

  $result{destroyed} = \@destroyed;

  return \%result;
}

sub ix_set ($self, $arg = {}, $ephemera = {}) {
  my $account_id = $Bakesale::Context::Context->account_id;

  my $rclass   = $self->_ix_rclass;
  my $type_key = $rclass->ix_type_key;
  my $schema   = $self->result_source->schema;

  # This whole mechanism should be provided by context -- rjbs, 2016-02-16
  # Really, should it? 😕  -- rjbs, 2016-02-18
  # Anyway, we need to create a row if none exists.
  my $state_row = $schema->resultset('States')->search({
    account_id => $account_id,
    type       => $type_key,
  })->first;

  $state_row //= $schema->resultset('States')->create({
    account_id => $account_id,
    type       => $type_key,
    state      => 1,
  });

  my $curr_state = $state_row->state;
  my $next_state = $curr_state + 1;

  # XXX THIS IS GARBAGE, fixed by putting state on context or something...
  # -- rjbs, 2016-02-18
  $ephemera->{next_state}{$type_key} = $next_state;

  # TODO validate everything

  if (($arg->{ifInState} // $curr_state) ne $curr_state) {
    return error('stateMismatch');
  }

  my %result;

  my $now = time;

  if ($arg->{create}) {
    my $create_result = $self->ix_create($arg->{create}, $ephemera);

    $result{created}     = $create_result->{created};
    $result{not_created} = $create_result->{not_created};

    $state_row->state($next_state) if keys $result{created}->%*;
  }

  if ($arg->{update}) {
    my $update_result = $self->ix_update($arg->{update}, $ephemera);

    $result{updated} = $update_result->{updated};
    $result{not_updated} = $update_result->{not_updated};
    $state_row->state($next_state) if $result{updated} && $result{updated}->@*;
  }

  if ($arg->{destroy}) {
    my $destroy_result = $self->ix_destroy($arg->{destroy}, $ephemera);

    $result{destroyed} = $destroy_result->{destroyed};
    $result{not_destroyed} = $destroy_result->{not_destroyed};
    $state_row->state($next_state) if $result{destroyed} && $result{destroyed}->@*;
  }

  $state_row->update;

  return Ix::Result::FoosSet->new({
    result_type => "${type_key}Set",
    old_state => $curr_state,
    new_state => $state_row->state,
    %result,
  });
}

1;
