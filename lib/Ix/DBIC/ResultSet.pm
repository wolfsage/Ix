use 5.20.0;
use warnings;
package Ix::DBIC::ResultSet;

use parent 'DBIx::Class::ResultSet';

use experimental qw(signatures postderef);

use Ix::Util qw(error internal_error parsedate result);
use JSON (); # XXX temporary?  for false() -- rjbs, 2016-02-22
use List::MoreUtils qw(uniq);
use Safe::Isa;

use namespace::clean;

# XXX Worth caching?  Probably. -- rjbs, 2016-05-10
sub _ix_rclass ($self) {
  my $rclass = $self->result_source->result_class;

  # Can this happen?  Who knows, probably! -- rjbs, 2016-02-20
  Carp::confess("called with non-Ix-compatible result class: $rclass")
    unless $rclass->isa('Ix::DBIC::Result');

  return $rclass;
}

my %HIDDEN_COLUMN = map {; $_ => 1 } qw(
  accountId
  modSeqCreated
  modSeqChanged
  dateDeleted
);

sub ix_get ($self, $ctx, $arg = {}) {
  my $accountId = $ctx->accountId;

  my $rclass    = $self->_ix_rclass;

  # XXX This is crap. -- rjbs, 2016-04-29
  $arg = $rclass->ix_preprocess_get_arg($arg)
    if $rclass->can('ix_preprocess_get_arg');

  my $ids   = $arg->{ids};
  my $since = $arg->{sinceState};

  my %is_prop = map  {; $_ => 1 }
                grep {; ! $HIDDEN_COLUMN{$_} }
                $self->result_source->columns;

  my @props;
  if ($arg->{properties}) {
    if (my @invalid = grep {; ! $is_prop{$_} } $arg->{properties}->@*) {
      return error("invalidArguments", {
        description       => "requested unknown property",
        unknownProperties => \@invalid,
      });
    }

    @props = uniq('id', $arg->{properties}->@*);
  } else {
    @props = keys %is_prop;
  }

  if (my $error = $rclass->ix_get_check($ctx, $arg)) {
    return $error;
  }

  my ($x_get_cond, $x_get_attr) = $rclass->ix_get_extra_search($ctx);

  my @rows = $self->search(
    {
      accountId => $accountId,
      (defined $since ? (modSeqChanged => { '>' => $since }) : ()),
      ($ids ? (id => $ids) : ()),
      dateDeleted => undef,
      %$x_get_cond,
    },
    {
      select => \@props,
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      %$x_get_attr,
    },
  )->all;

  $self->_ix_wash_rows(\@rows);

  my @not_found;
  if ($ids) {
    my %found  = map  {; $_->{id} => 1 } @rows;
    @not_found = grep {; ! $found{$_} } @$ids;
  }

  return result($rclass->ix_type_key => {
    state => $rclass->ix_state_string($ctx->state),
    list  => \@rows,
    notFound => (@not_found ? \@not_found : undef),
  });
}

sub ix_get_updates ($self, $ctx, $arg = {}) {
  my $accountId = $ctx->accountId;

  my $since = $arg->{sinceState};

  return error(invalidArguments => { description => "no sinceState given" })
    unless defined $since;

  my $limit = $arg->{maxChanges};
  if (defined $limit && ( $limit !~ /^[0-9]+\z/ || $limit == 0 )) {
    return error(invalidArguments => { description => "invalid maxChanges" });
  }

  my $rclass   = $self->_ix_rclass;
  my $type_key = $rclass->ix_type_key;
  my $schema   = $self->result_source->schema;
  my $res_type = $rclass->ix_type_key_singular . "Updates";

  my $statecmp = $rclass->ix_compare_state($since, $ctx->state);

  die "wtf happened" unless $statecmp->$_isa('Ix::StateComparison');

  if ($statecmp->is_in_sync) {
    return result($res_type => {
      oldState => "$since",
      newState => "$since",
      hasMoreUpdates => JSON::false(), # Gross. -- rjbs, 2016-02-21
      changed => [],
      removed => [],
    });
  }

  if ($statecmp->is_bogus) {
    error(invalidArguments => { description => "invalid sinceState" })->throw;
  }

  if ($statecmp->is_resync) {
    error(cannotCalculateChanges => {
      description => "client cache must be reconstucted"
    })->throw
  }

  my %is_prop = map  {; $_ => 1 }
                grep {; ! $HIDDEN_COLUMN{$_} }
                $self->result_source->columns;

  my @invalid_props;

  my @props;
  if ($arg->{fetchRecords} && $arg->{fetchRecordProperties}) {
    if (@invalid_props = grep {; ! $is_prop{$_} } $arg->{fetchRecordProperties}->@*) {
      @props = 'id';
    }

    @props = uniq('id', $arg->{fetchRecordProperties}->@*);
  } elsif ($arg->{fetchRecords}) {
    @props = keys %is_prop;
  } else {
    @props = 'id';
  }

  my ($x_get_cond, $x_get_attr) = $rclass->ix_get_extra_search($ctx);

  my ($x_update_cond, $x_update_attr) = $rclass->ix_update_extra_search($ctx, {
    since => $since,
  });

  my $state_string_field = $rclass->ix_update_state_string_field;

  my $search = $self->search(
    {
      'me.accountId'     => $accountId,
      %$x_get_cond,
      %$x_update_cond,
    },
    {
      select => [
        @props,
        qw(me.dateDeleted me.modSeqChanged),
        $rclass->ix_update_extra_select->@*,
      ],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      order_by => 'me.modSeqChanged',
      %$x_get_attr,
      %$x_update_attr,
    },
  );

  my @rows = $search->search(
    {},
    {
      ($limit ? (rows => $limit + 1) : ()),
    },
  )->all;

  my $hasMoreUpdates = 0;

  if ($limit && @rows > $limit) {
    # So, the user asked for (say) 100 rows.  We'll drop the whole set of
    # records from the highest-seen state, and let the user know that more
    # changes await.  We ask for one more row than is needed so that if we were
    # at a state boundary, we can get the limit-count worth of rows by dropping
    # only the superfluous one. -- rjbs, 2016-05-04
    $hasMoreUpdates = 1;

    my $maxState = $rows[$limit]{$state_string_field};
    my @trimmed_rows = grep { $_->{$state_string_field} ne $maxState } @rows;

    if (@trimmed_rows == 0) {
      # ... well, it turns out that the entire batch was in one state.  We
      # can't possibly provide a consistent update within the bounds that the
      # user requested.  When this happens, we're permitted to provide more
      # records than requested, so let's just fetch one state worth of
      # records. -- rjbs, 2016-02-22
      @rows = $search->search(
        $rclass->ix_update_single_state_conds($rows[0])
      )->all;
    } else {
      @rows = @trimmed_rows;
    }
  }

  my @changed;
  my @removed;
  for my $item (@rows) {
    if ($item->{dateDeleted}) {
      push @removed, "$item->{id}";
    } else {
      push @changed, $item;
    }
  }

  my @return = result($res_type => {
    oldState => "$since",
    newState => ($hasMoreUpdates
              ? $rclass->ix_highest_state($since, \@rows)
              : $rclass->ix_state_string($ctx->state)),
    hasMoreUpdates => $hasMoreUpdates ? JSON::true() : JSON::false(),
    changed => [ map {; "$_->{id}" } @changed ],
    removed => \@removed,
  });

  if ($arg->{fetchRecords}) {
    if (@invalid_props) {
      push @return, error(invalidArguments => {
        description       => "requested unknown property",
        unknownProperties => \@invalid_props,
      });
    } else {
      my @rows = map {; +{ $_->%{ @props } } } @changed;
      $self->_ix_wash_rows(\@rows);

      my %found = map {; $_->{id} => 1 } @rows;
      my @not_found = grep {; ! $found{ $_ } }
                      map  {; "$_->{id}" }
                      @changed;

      push @return, result($type_key => {
        state => $rclass->ix_state_string($ctx->state),
        list  => \@rows,
        notFound => (@not_found ? \@not_found : undef),
      });
    }
  }

  return @return;
}

sub ix_purge ($self, $ctx) {
  my $accountId = $ctx->accountId;

  my $rclass = $self->_ix_rclass;

  my $type_key = $rclass->ix_type_key;

  my $since = Ix::DateTime->from_epoch(epoch => time - 86400 * 7);

  my $rs = $self->search({
    accountId   => $accountId,
    dateDeleted => { '<', $since->as_string },
  });

  my $maxDeletedModSeq = $self->get_column('modSeqChanged')->max;

  $rs->delete;

  # XXX: violating encapsulation
  my $state_row = $ctx->state->_state_rows->{$type_key};

  $state_row->lowestModSeq( $maxDeletedModSeq )
    if $maxDeletedModSeq > $state_row->lowestModSeq;

  return;
}

sub ix_create ($self, $ctx, $to_create) {
  my $accountId = $ctx->accountId;

  my $rclass = $self->_ix_rclass;

  my $type_key = $rclass->ix_type_key;

  my $next_state = $ctx->state->next_state_for($type_key);

  my %result;

  # TODO do this once during ix_finalize -- rjbs, 2016-05-10
  my %is_user_prop = map {; $_ => 1 } $rclass->ix_user_property_names;

  my %default_properties = (
    # XXX: This surely must require a lot more customizability; pass in
    # context, user props, blah blah blah.  A bigger question is whether we can
    # have this work only on context, and not on the properties so far.  (Can a
    # property specified by the user alter the default that we'll put on a new
    # object?) -- rjbs, 2016-06-02
    $rclass->ix_default_properties($ctx)->%*,
  );

  my $col_info = $rclass->columns_info;
  my @date_fields = grep {; ($col_info->{$_}{data_type} // '') eq 'datetime' }
                    keys %$col_info;

  # TODO: sort these in dependency order, so if item A references item B, B is
  # created first -- rjbs, 2016-05-10
  my @keys = keys $to_create->%*;

  TO_CREATE: for my $id (@keys) {
    my $this = $to_create->{$id};

    my ($user_prop, $property_error) = $self->_ix_check_user_properties(
      $ctx,
      $this,
      \%is_user_prop,
      \%default_properties,
      $col_info,
    );

    if (%$property_error) {
      $result{not_created}{$id} = error(invalidProperties => {
        description => "invalid property values",
        propertyErrors => $property_error,
      });
      next TO_CREATE;
    }

    my %rec = (
      %$user_prop,
      %default_properties,

      accountId => $accountId,
      modSeqCreated => $next_state,
      modSeqChanged => $next_state,
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
      $result{not_created}{$id} = error(invalidProperties => {
        description => "invalid date values",
        properties  => \@bogus_dates,
      });
      next TO_CREATE;
    }

    if (my $error = $rclass->ix_create_check($ctx, \%rec)) {
      $result{not_created}{$id} = $error;
      next TO_CREATE;
    }

    my $row = eval {
      $ctx->schema->txn_do(sub {
        $self->create(\%rec);
      });
    };

    if ($row) {
      # This is silly.  Can we get a pair slice out of a Row?
      $result{created}{$id} = { id => $row->id, %default_properties };

      $ctx->log_created_id($type_key, $id, $row->id);
    } else {
      $result{not_created}{$id} = error(
        'invalidRecord', { description => "could not create" },
        "database rejected creation", { db_error => "$@" },
      );
    }
  }

  $self->_ix_wash_rows([ values $result{created}->%* ]);

  return \%result;
}

sub _ix_check_user_properties (
  $self, $ctx, $rec, $is_user_prop, $defaults, $col_info
) {
  my %user_prop;
  my %property_error;

  PROP: for my $prop (keys %$rec) {
    my $value = $rec->{$prop};

    unless ($is_user_prop->{$prop}) {
      $property_error{$prop} = "unknown property";
      next PROP;
    }

    if (
      $value->$_isa('JSON::PP::Boolean') || $value->$_isa('JSON::XS::Boolean')
    ) {
      $value = $value ? 1 : 0;
    }

    if (ref $value && ! $value->$_isa('Ix::DateTime')) {
      $property_error{$prop} = "invalid property value";
      next PROP;
    }

    my $col = $col_info->{$prop};

    if (
      # Probably we can intuit this from foreign keys or relationships?
      (my $xref_type = $col->{ix_xref_to})
      &&
      $value && $value =~ /\A#(.+)\z/
    ) {
      if (my $xref = $ctx->get_created_id($xref_type, "$1")) {
        $value = $xref;
      } else {
        $property_error{$prop} = "can't resolve creation id";
        next PROP;
      }
    }

    if (my $validator = $col->{ix_validator}) {
      if (my $error = $validator->($value)) {
        $property_error{$prop} = $error;
        next PROP;
      }
    }

    $user_prop{$prop} = $value;
  }

  # $defaults being defined means we're doing a create, not an update
  if ($defaults) {
    for my $prop (
      grep { ! defined $rec->{$_} && ! $defaults->{$_} }
      keys %$is_user_prop
    ) {
      next if $col_info->{$prop}->{is_nullable};
      $property_error{$prop} = "no value given for required field";
    }
  }

  return (\%user_prop, \%property_error);
}

sub _ix_wash_rows ($self, $rows) {
  my $rclass = $self->_ix_rclass;
  my $info   = $self->result_source->columns_info;

  my %by_type;
  for my $key (keys %$info) {
    my $type = $info->{$key}{ix_data_type};
    push $by_type{$type}->@*, $key if $type;
  }

  my $true  = JSON::true();
  my $false = JSON::false();

  for my $row (@$rows) {
    for my $key ($by_type{integer}->@*) {
      $row->{$key} = 0 + $row->{$key} if defined $row->{$key};
    }

    for my $key ($by_type{string}->@*) {
      $row->{$key} = "$row->{$key}" if defined $row->{$key};
    }

    for my $key ($by_type{boolean}->@*) {
      $row->{$key} = $row->{$key} ? $true : $false if defined $row->{$key};
    }
  }

  $rclass->_ix_wash_rows($rows) if $rclass->can('_ix_wash_rows');

  return;
}

sub ix_update ($self, $ctx, $to_update) {
  my $accountId = $ctx->accountId;

  my $rclass = $self->_ix_rclass;

  my %result;

  my $type_key   = $rclass->ix_type_key;
  my $next_state = $ctx->state->next_state_for($type_key);

  my @updated;

  # TODO do this once during ix_finalize -- rjbs, 2016-05-10
  my %is_user_prop = map {; $_ => 1 } $rclass->ix_user_property_names;
  my $col_info = $rclass->columns_info;

  UPDATE: for my $id (keys $to_update->%*) {
    my $row = $self->find({
      id => $id,
      accountId   => $accountId,
      dateDeleted => undef,
    });

    unless ($row) {
      $result{not_updated}{$id} = error(notFound => {
        description => "no such record found",
      });
      next UPDATE;
    }

    my ($user_prop, $property_error) = $self->_ix_check_user_properties(
      $ctx,
      $to_update->{$id},
      \%is_user_prop,
      undef,
      $col_info,
    );

    if (%$property_error) {
      $result{not_updated}{$id} = error(invalidProperties => {
        description => "invalid property values",
        propertyErrors => $property_error,
      });
      next UPDATE;
    }

    if (my $error = $rclass->ix_update_check($ctx, $to_update->{$id})) {
      $result{not_updated}{$id} = $error;
      next UPDATE;
    }

    my $ok = eval {
      $ctx->schema->txn_do(sub {
        $row->update({
          %$user_prop,
          modSeqChanged => $next_state,
        });
      });
    };

    if ($ok) {
      push @updated, $id;
    } else {
      $result{not_updated}{$id} = error(
        'invalidRecord', { description => "could not update" },
        "database rejected update", { db_error => "$@" },
      );
    }
  }

  $result{updated} = \@updated;

  return \%result;
}

sub ix_destroy ($self, $ctx, $to_destroy) {
  my $accountId = $ctx->accountId;

  my $rclass = $self->_ix_rclass;

  my $type_key   = $rclass->ix_type_key;
  my $next_state = $ctx->state->next_state_for($type_key);

  my %result;

  my @destroyed;
  DESTROY: for my $id ($to_destroy->@*) {
    my $row = $self->search({
      id => $id,
      accountId => $accountId,
      dateDeleted => undef,
    })->first;

    unless ($row) {
      $result{not_destroyed}{$id} = error(notFound => {
        description => "no such record found",
      });
      next DESTROY;
    }

    if (my $error = $rclass->ix_destroy_check($ctx, $row)) {
      $result{not_destroyed}{$id} = $error;
      next DESTROY;
    }

    my $ok = eval {
      $ctx->schema->txn_do(sub {
        $row->update({
          modSeqChanged => $next_state,
          dateDeleted   => Ix::DateTime->now,
        });
        return 1;
      });
    };

    if ($ok) {
      push @destroyed, $id;
    } else {
      $result{not_destroyed}{$id} = internal_error(
        "database rejected delete", { db_error => "$@" },
      );
    }
  }

  $result{destroyed} = \@destroyed;

  return \%result;
}

sub ix_set ($self, $ctx, $arg = {}) {
  my $accountId = $ctx->accountId;

  my $rclass   = $self->_ix_rclass;
  my $type_key = $rclass->ix_type_key;
  my $schema   = $self->result_source->schema;

  my $state = $ctx->state;
  my $curr_state = $state->state_for($type_key);

  # TODO validate everything

  if (($arg->{ifInState} // $curr_state) ne $curr_state) {
    return error('stateMismatch');
  }

  my %result;

  if ($arg->{create}) {
    my $create_result = $self->ix_create($ctx, $arg->{create});

    $result{created}     = $create_result->{created};
    $result{not_created} = $create_result->{not_created};

    $state->ensure_state_bumped($type_key) if keys $result{created}->%*;
  }

  if ($arg->{update}) {
    my $update_result = $self->ix_update($ctx, $arg->{update});

    $result{updated} = $update_result->{updated};
    $result{not_updated} = $update_result->{not_updated};
    $state->ensure_state_bumped($type_key) if $result{updated} && $result{updated}->@*;
  }

  if ($arg->{destroy}) {
    my $destroy_result = $self->ix_destroy($ctx, $arg->{destroy});

    $result{destroyed} = $destroy_result->{destroyed};
    $result{not_destroyed} = $destroy_result->{not_destroyed};
    $state->ensure_state_bumped($type_key) if $result{destroyed} && $result{destroyed}->@*;
  }

  return Ix::Result::FoosSet->new({
    result_type => "${type_key}Set",
    old_state => $curr_state,
    new_state => $rclass->ix_state_string($state),
    %result,
  });
}

1;
