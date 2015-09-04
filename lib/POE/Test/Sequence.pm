package POE::Test::Sequence;

use warnings;
use strict;

use Carp qw(croak);
use POE;

sub new {
  my ($class, %args) = @_;

  my $sequence = delete $args{sequence};
  croak "sequence required" unless defined $sequence;

  return bless {
    sequence   => $sequence,
    test_count => scalar( @$sequence ),
  }, $class;
}

sub next {
  my ($self, $event, $parameter) = @_;

  my $expected_result = shift @{ $self->{sequence} };
  unless (defined $expected_result) {
    Test::More::fail(
      "Got an unexpected result ($event, $parameter). Time to bye."
    );
    exit;
  }

  my $next_action = pop @$expected_result;

  Test::More::note "Testing (@$expected_result)";

  Test::More::is_deeply( [ $event, $parameter ], $expected_result );

  return $next_action || sub { undef };
}

sub test_count {
  return $_[0]{test_count};
}

sub create_generic_session {
  my ($self) = @_;

  POE::Session->create(
    inline_states => {
      _start   => sub { goto $self->next( $_[STATE], 0 ) },
      _default => sub { goto $self->next( $_[ARG0],  0 ) },
    }
  );
}

1;

__END__

=head1 NAME

POE::Test::Sequence - POE test helper to verify a sequence of events

=head1 SYNOPSIS

  Sorry, there isn't a synopsis at this time.

  However, see t/90_regression/whjackson-followtail.t in POE's test
  suite for a full example.

=head1 DESCRIPTION

POE::Test::Sequence is a test helper that abstracts a lot of the
tedious trickery needed to verify the relative ordering of events.

With this module, one can test the sequence of events without
necessarily relying on specific times elapsing between them.

=head2 create_generic_session

The create_generic_session() method creates a POE::Session that routes
all vents through the POE::Test::Sequence object.  It returns the
POE::Session object, but the test program does not need to store it
anywhere.  In fact, it's recommended not to do that without
understanding the implications.

The implications can be found in the documentation for POE::Kernel and
POE::Session.

An example of create_generic_session() can be found in
POE's t/90_regression/leolo-alarm-adjust.t test program.

=head2 new

Create a new sequence object.  Takes named parameter pairs, currently
just "sequence", which references an array of steps.  Each step is an
array reference containing the expected event, a required parameter to
that event, and a code reference for the optional next step to take
after testing for that event.

  my $sequence = POE::Test::Sequence->new(
    sequence => [
    [ got_idle_event => 0, sub { append_to_log("text") } ],
    ...,
  ]
  );

next() uses the first two step elements to verify that steps are
occurring in the order in which they should.  The third element is
returned by next() and is suitable for use as a goto() target.  See
the next() method for more details.

=head2 next

The next() method requires an event name and a scalar parameter.
These are compared to the first two elements of the next sequence step
to make sure events are happening in the order in which they should.

  sub handle_start_event {
    goto $sequence->next("got_start_event", 0);
  }

=head2 test_count

test_count() returns the number of test steps in the sequence object.
It's intended to be used for test planning.

  use Test::More;
  my $sequence = POE::Test::Sequence->new( ... );
  plan tests => $sequence->test_count();

=head1 BUGS

create_generic_session() is hard-coded to pass only the event name and
the numeric value 0 to next().  This is fine for only the most generic
sequences.

=head1 AUTHORS & LICENSING

Please see L<POE> for more information about authors, contributors,
and POE's licensing.

=cut

# vim: ts=2 sw=2 filetype=perl expandtab
