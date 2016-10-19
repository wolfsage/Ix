package Bakesale::Context {;
  use Moose;

  use experimental qw(lexical_subs signatures postderef);

  use Data::GUID qw(guid_string);

  use namespace::autoclean;

  sub is_system { 0 }

  sub file_exception_report {
    warn "EXCEPTION!!";
    return guid_string();
  }

  has userId => (
    is       => 'ro',
    required => 1,
  );

  has user => (
    isa      => 'Object',
    reader   => 'user',
    writer   => '_set_user',
    init_arg => undef,
    lazy     => 1,
    clearer  => '_clear_user', # trigger this after setUsers, surely?
    default  => sub ($self) {
      return $self->schema->resultset('User')->find($self->userId);
    },
  );

  sub with_dataset ($self, $t, $i) {
    $self->internal_error("unknown dataset type: $t")->throw
      unless $t eq 'generic';

    $i //= $self->user->datasetId;

    $self->error("invalidArgument" => {})->throw
      unless $i eq $self->user->datasetId;

    return Bakesale::Context::WithDataset->new({
      root_context => $self,
      dataset_type => $t,
      datasetId    => $i,
    });
  }

  with 'Ix::Context';
}

package Bakesale::Context::System {
  use Moose;

  use experimental qw(lexical_subs signatures postderef);
  use namespace::autoclean;

  sub with_dataset ($self, $t, $i) {
    return Bakesale::Context::WithDataset->new({
      root_context => $self,
      dataset_type => $t,
      datasetId    => $i,
    });
  }

  sub is_system { 1 }

  with 'Ix::Context';
}

package Bakesale::Context::WithDataset {
  use Moose;

  use experimental qw(lexical_subs signatures postderef);
  use namespace::autoclean;

  sub dataset_type { 'generic' }
  has datasetId => (is => 'ro', isa => 'Str', required => 1);

  with 'Ix::Context::WithDataset';
}

1;
