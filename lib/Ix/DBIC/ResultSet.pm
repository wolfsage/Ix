use 5.20.0;
use warnings;
package Ix::DBIC::ResultSet;

use parent 'DBIx::Class::ResultSet';

use experimental qw(signatures postderef);

use Ix::Util qw(error parsedate result);
use List::MoreUtils qw(uniq);
use Safe::Isa;

use namespace::clean;

sub _ix_rclass ($self) {
  my $rclass = $self->result_source->result_class;

  # Can this happen?  Who knows, probably! -- rjbs, 2016-02-20
  Carp::confess("called with non-Ix-compatible result class: $rclass")
    unless $rclass->isa('Ix::DBIC::Result');

  return $rclass;
}

sub ix_get ($self, $arg = {}, $ephemera = {}) {
  my $accountId = $Bakesale::Context::Context->accountId;

  my $rclass    = $self->_ix_rclass;
  my $state_row = $self->_curr_state_row($rclass);

  my $ids   = $arg->{ids};
  my $since = $arg->{sinceState};

  my %is_prop = map  {; $_ => 1 }
                grep {; $_ ne 'accountId' && $_ ne 'state' }
                $self->result_source->columns;

  my @props;
  if ($arg->{properties}) {
    if (my @invalid = grep {; ! $is_prop{$_} } $arg->{properties}->@*) {
      return error("propertyError", {
        description       => "requested unknown property",
        unknownProperties => \@invalid,
      });
    }

    @props = uniq('id', $arg->{properties}->@*);
  } else {
    @props = keys %is_prop;
  }

  my @rows = $self->search(
    {
      accountId => $accountId,
      (defined $since ? (state => { '>' => $since }) : ()),
      ($ids ? (id => $ids) : ()),
    },
    {
      select => \@props,
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    },
  )->all;

  # TODO: populate notFound result property
  return result($rclass->ix_type_key => {
    state => $state_row->state,
    list  => \@rows,
    notFound => undef, # TODO
  });
}

sub ix_create ($self, $to_create, $ephemera) {
  my $accountId = $Bakesale::Context::Context->accountId;

  my $rclass = $self->_ix_rclass;

  my $type_key = $rclass->ix_type_key;

  # XXX: this is garbage, fix it -- rjbs, 2016-02-18
  my $next_state = $ephemera->{next_state}{$type_key};

  # TODO handle unknown properties
  my $error = error('invalidRecord', { description => "could not create" });

  my %result;

  my $now = time; # pull off of context? -- rjbs, 2016-02-18

  my @user_props = $rclass->ix_user_property_names;

  my $info = $self->result_source->columns_info;
  my @date_fields = grep {; ($info->{$_}{data_type} // '') eq 'datetime' }
                    keys %$info;

  TO_CREATE: for my $id (keys $to_create->%*) {
    my %user_props = @user_props ? $to_create->{$id}->%{@user_props} : ();
    if (my @bogus = grep {; ref $user_props{$_} && ! $user_props{$_}->$_isa('Ix::DateTime') } keys %user_props) {
      $result{not_created}{$id} = error(invalidProperty => {
        description => "invalid property values",
        invalidProperties => \@bogus,
      });
      next TO_CREATE;
    }

    my %default_properties = (
      # XXX: this surely must require a lot more customizability; pass in
      # context, user props, blah blah blah
      $rclass->ix_default_properties->%*,
    );

    my %rec = (
      # barf if there are unexpected properties, don't just drop them
      # -- rjbs, 2016-02-18
      %user_props,
      %default_properties,

      accountId => $accountId,
      state      => $next_state,
    );

    my @bogus_dates;
    DATE_FIELD: for my $date_field (@date_fields) {
      next DATE_FIELD unless exists $rec{$date_field};
      if (ref $rec{ $date_field }) {
        # $rec{$date_field} = $rec{ $date_field }->as_string;
        next DATE_FIELD;
      }

      if (my $dt = parsedate($rec{$_})) {
        # great, it's already valid
        $rec{$date_field} = $dt;
      } else {
        push @bogus_dates, $_;
      }
    }

    if (@bogus_dates) {
      $result{not_created}{$id} = error(invalidProperty => {
        description => "invalid date values",
        invalidProperties => \@bogus_dates,
      });
      next TO_CREATE;
    }

    my $row = eval { $self->create(\%rec); };

    if ($row) {
      # This is silly.  Can we get a pair slice out of a Row?
      $result{created}{$id} = { id => $row->id, %default_properties };

      $ephemera->{$type_key}{$id} = $row->id;
    } else {
      $result{not_created}{$id} = $error;
    }
  }

  return \%result;
}

sub ix_update ($self, $to_update, $ephemera) {
  my $accountId = $Bakesale::Context::Context->accountId;

  my $rclass = $self->_ix_rclass;

  my %result;

  my @updated;
  my $error = error('invalidRecord', { description => "could not update" });
  for my $id (keys $to_update->%*) {
    my $row = $self->find({ id => $id, accountId => $accountId });

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
  my $accountId = $Bakesale::Context::Context->accountId;

  my $rclass = $self->_ix_rclass;

  my %result;

  my @destroyed;
  for my $id ($to_destroy->@*) {
    my $rv = $self->search({ id => $id, accountId => $accountId })
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

sub _curr_state_row ($self, $rclass) {
  # This whole mechanism should be provided by context -- rjbs, 2016-02-16
  # Really, should it? 😕  -- rjbs, 2016-02-18
  # Anyway, we need to create a row if none exists.
  my $accountId = $Bakesale::Context::Context->accountId;

  my $states_rs = $self->result_source->schema->resultset('States');

  my $state_row = $states_rs->search({
    accountId => $accountId,
    type       => $rclass->ix_type_key,
  })->first;

  $state_row //= $states_rs->create({
    accountId => $accountId,
    type       => $rclass->ix_type_key,
    state      => 1,
  });
}

sub ix_set ($self, $arg = {}, $ephemera = {}) {
  my $accountId = $Bakesale::Context::Context->accountId;

  my $rclass   = $self->_ix_rclass;
  my $type_key = $rclass->ix_type_key;
  my $schema   = $self->result_source->schema;

  my $state_row  = $self->_curr_state_row($rclass);
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
