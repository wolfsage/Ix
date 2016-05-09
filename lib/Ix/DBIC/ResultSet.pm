use 5.20.0;
use warnings;
package Ix::DBIC::ResultSet;

use parent 'DBIx::Class::ResultSet';

use experimental qw(signatures postderef);

use Ix::Util qw(error parsedate result);
use JSON (); # XXX temporary?  for false() -- rjbs, 2016-02-22
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

my %HIDDEN_COLUMN = map {; $_ => 1 } qw(
  accountId
  modSeqCreated
  modSeqChanged
  dateDeleted
);

sub ix_get ($self, $ctx, $arg = {}) {
  my $accountId = $ctx->{accountId};

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

  my @rows = $self->search(
    {
      accountId => $accountId,
      (defined $since ? (modSeqChanged => { '>' => $since }) : ()),
      ($ids ? (id => $ids) : ()),
      dateDeleted => undef,
    },
    {
      select => \@props,
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    },
  )->all;

  $self->_ix_wash_rows(\@rows);

  # TODO: populate notFound result property
  return result($rclass->ix_type_key => {
    state => $rclass->ix_state_string($ctx->state),
    list  => \@rows,
    notFound => undef, # TODO
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

  my ($extra_search, $extra_attr) = $rclass->ix_update_extra_search({
    since => $since,
  });

  my $state_string_field = $rclass->ix_update_state_string_field;

  my $search = $self->search(
    {
      'me.accountId'     => $accountId,
      %$extra_search,
    },
    {
      select => [
        @props,
        qw(me.dateDeleted me.modSeqChanged),
        $rclass->ix_update_extra_select->@*,
      ],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      order_by => 'me.modSeqChanged',
      %$extra_attr,
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

      push @return, result($type_key => {
        state => $rclass->ix_state_string($ctx->state),
        list  => \@rows,
        notFound => undef, # TODO
      });
    }
  }

  return @return;
}

sub ix_purge ($self, $ctx) {
  my $accountId = $ctx->{accountId};

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

  # TODO handle unknown properties
  my $error = error('invalidRecord', { description => "could not create" });

  my %result;

  my $now = time; # pull off of context? -- rjbs, 2016-02-18

  my @user_props = $rclass->ix_user_property_names;

  my $info = $self->result_source->columns_info;
  my @date_fields = grep {; ($info->{$_}{data_type} // '') eq 'datetime' }
                    keys %$info;

  my @keys = keys $to_create->%*;

  TO_CREATE: for my $id (@keys) {
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
      $result{not_created}{$id} = error(invalidProperty => {
        description => "invalid date values",
        invalidProperties => \@bogus_dates,
      });
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

      $ctx->{ix_ephemera}{$type_key}{$id} = $row->id;
    } else {
      $result{not_created}{$id} = $error;
    }
  }

  $self->_ix_wash_rows([ values $result{created}->%* ]);

  return \%result;
}

sub _ix_wash_rows ($self, $rows) {
  my $rclass = $self->_ix_rclass;
  my $info   = $self->result_source->columns_info;

  my @num_fields = grep {; ($info->{$_}{data_type} // '') eq 'integer' } keys %$info;
  my @str_fields = grep {; ($info->{$_}{data_type} // '') eq 'text' }    keys %$info;
  my @boo_fields = grep {; ($info->{$_}{data_type} // '') eq 'boolean' } keys %$info;

  my $true  = JSON::true();
  my $false = JSON::false();

  for my $row (@$rows) {
    for my $key (@num_fields) {
      $row->{$key} = 0 + $row->{$key} if defined $row->{$key};
    }

    for my $key (@str_fields) {
      $row->{$key} = "$row->{$key}" if defined $row->{$key};
    }

    for my $key (@boo_fields) {
      $row->{$key} = $row->{$key} ? $true : $false if defined $row->{$key};
    }

    $row->{id} = "$row->{id}" if defined $row->{id};
  }

  $rclass->_ix_wash_rows($rows) if $rclass->can('_ix_wash_rows');

  return;
}

sub ix_update ($self, $ctx, $to_update) {
  my $accountId = $ctx->{accountId};

  my $rclass = $self->_ix_rclass;

  my %result;

  my $type_key   = $rclass->ix_type_key;
  my $next_state = $ctx->state->next_state_for($type_key);

  my @updated;
  my $error = error('invalidRecord', { description => "could not update" });
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

    # TODO: validate the update -- rjbs, 2016-02-16
    my $ok = eval {
      $ctx->schema->txn_do(sub {
        $row->update({
          $to_update->{$id}->%*,
          modSeqChanged => $next_state,
        });
      });
    };

    if ($ok) {
      push @updated, $id;
    } else {
      $result{not_updated}{$id} = $error;
    }
  }

  $result{updated} = \@updated;

  return \%result;
}

sub ix_destroy ($self, $ctx, $to_destroy) {
  my $accountId = $ctx->{accountId};

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
      $result{not_destroyed}{$id} = error('failedToDelete');
    }
  }

  $result{destroyed} = \@destroyed;

  return \%result;
}

sub ix_set ($self, $ctx, $arg = {}) {
  my $accountId = $ctx->{accountId};

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

  my $now = time;

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
