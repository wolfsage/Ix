use strict;
use warnings;
use experimental qw(postderef signatures);
package Bakesale::Schema::Result::Cake;
use base qw/DBIx::Class::Core/;

use Ix::Validators qw(integer nonemptystr);
use List::Util qw(max);

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

__PACKAGE__->table('cakes');

__PACKAGE__->ix_add_columns;

__PACKAGE__->ix_add_properties(
  type        => { data_type => 'text',     },
  layer_count => { data_type => 'integer',  validator => integer(1, 10)  },
  baked_at    => { data_type => 'datetime', is_immutable => 1 },
  recipe_id    => { data_type => 'integer',  xref_to => 'cakeRecipes' },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cakes' }

sub ix_default_properties {
  return { baked_at => Ix::DateTime->now };
}

sub ix_get_check ($self, $ctx, $arg) {
  return if $arg->{ids};

  return $ctx->error(invalidArguments => {
    description => "required parameter 'ids' not present",
  });
}

sub ix_state_string ($self, $state) {
  return join q{-},
    $state->state_for($self->ix_type_key),
    $state->state_for('cakeRecipes');
}

sub ix_compare_state ($self, $since, $state) {
  my ($cake_since, $recipe_since) = split /-/, $since, 2;

  return Ix::StateComparison->bogus
    unless ($cake_since//'')    =~ /\A[0-9]+\z/
        && ($recipe_since//'')  =~ /\A[0-9]+\z/;

  my $cake_high   = $state->highest_modseq_for('cakes');
  my $recipe_high = $state->highest_modseq_for('cakeRecipes');

  my $cake_low    = $state->lowest_modseq_for('cakes');
  my $recipe_low  = $state->lowest_modseq_for('cakeRecipes');

  if ($cake_high < $cake_since || $recipe_high < $recipe_since) {
    return Ix::StateComparison->bogus;
  }

  if ($cake_low >= $cake_since || $recipe_low >= $recipe_since) {
    return Ix::StateComparison->resync;
  }

  if ($cake_high == $cake_since && $recipe_high == $recipe_since) {
    return Ix::StateComparison->in_sync;
  }

  return Ix::StateComparison->okay;
}

sub ix_update_state_string_field { 'joint_mod_seq' }

sub ix_highest_state ($self, $since, $rows) {
  my ($cake_since,  $recipe_since)  = split /-/, $since, 2;

  my @r_updates = grep { $_->{joint_mod_seq} =~ /A-/ } @$rows;
  my @c_updates = grep { $_->{joint_mod_seq} =~ /B-/ } @$rows;

  my ($r_max) = @r_updates ? ($r_updates[-1]{joint_mod_seq} =~ /-([0-9]+)\z/) : $recipe_since;
  my ($c_max) = @c_updates ? ($c_updates[-1]{joint_mod_seq} =~ /-([0-9]+)\z/) : $cake_since;

  return "$c_max-$r_max";
}

sub ix_update_extra_search ($self, $ctx, $arg) {
  my $since = $arg->{since};

  my ($cake_since, $recipe_since) = split /-/, $since, 2;
  die "bogus state?!"
    unless ($cake_since//'')    =~ /\A[0-9]+\z/
        && ($recipe_since//'')  =~ /\A[0-9]+\z/;

  return(
    {
      -or => [
        'me.mod_seq_changed'     => { '>' => $cake_since },
        'recipe.mod_seq_changed' => { '>' => $recipe_since },
      ],
    },
    {
      '+columns' => {
        joint_mod_seq  => \[
          q{(CASE WHEN ? < recipe."mod_seq_changed" THEN ('A-' || recipe."mod_seq_changed") ELSE ('B-' || me."mod_seq_changed") END)},
          $recipe_since,
        ],
      },
      join => [ 'recipe' ],

      order_by => [
        # Here, we only do A/B because we can't sort by A-n/B-n, because A-11
        # will sort before A-2.  On the other hand, we only use the joint_mod_seq
        # above for checking equality, not ordering, so it is appropriate to
        # use a string. -- rjbs, 2016-05-09
        \[
          q{(CASE WHEN ? < recipe."mod_seq_changed" THEN 'A' ELSE 'B' END)},
          $recipe_since,
        ],
        \[
          q{(CASE WHEN ? < recipe."mod_seq_changed" THEN recipe."mod_seq_changed" ELSE me."mod_seq_changed" END)},
          $recipe_since,
        ],
      ],
    },
  );
}

sub ix_update_single_state_conds ($self, $example_row) {
  if ($example_row->{joint_mod_seq} =~ /\AA-([0-9]+)\z/) {
    return { 'recipe.mod_seq_changed' => "$1" }
  } elsif ($example_row->{joint_mod_seq} =~ /\AB-([0-9]+)\z/) {
    return { 'me.mod_seq_changed' => "$1" }
  }

  Carp::confess("Unreachable code reached.");
}

__PACKAGE__->belongs_to(
  recipe => 'Bakesale::Schema::Result::CakeRecipe',
  { 'foreign.id' => 'self.recipe_id' },
);

1;
