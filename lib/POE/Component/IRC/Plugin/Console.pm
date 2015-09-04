package POE::Component::IRC::Plugin::Console;
BEGIN {
  $POE::Component::IRC::Plugin::Console::AUTHORITY = 'cpan:HINRIK';
}
$POE::Component::IRC::Plugin::Console::VERSION = '6.88';
use strict;
use warnings FATAL => 'all';
use Carp;
use IRC::Utils qw(decode_irc);
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::IRCD Filter::Line Filter::Stackable);
use POE::Component::IRC::Plugin qw( :ALL );
use Scalar::Util qw(looks_like_number);

sub new {
    my $package = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %self = @_;
    return bless \%self, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;

    $self->{irc} = $irc;

    $irc->plugin_register( $self, 'SERVER', qw(all) );
    $irc->plugin_register( $self, 'USER', qw(all) );

    POE::Session->create(
        object_states => [
            $self => [ qw(_client_error _client_flush _client_input _listener_accept _listener_failed _start _shutdown) ],
        ],
    );

    return 1;
}

sub PCI_unregister {
    my ($self, $irc) = splice @_, 0, 2;

    delete $self->{irc};
    $poe_kernel->post( $self->{SESSION_ID} => '_shutdown' );
    $poe_kernel->refcount_decrement( $self->{SESSION_ID}, __PACKAGE__ );
    return 1;
}

sub _dump {
    my ($arg) = @_;

    if (ref $arg eq 'ARRAY') {
        my @elems;
        for my $elem (@$arg) {
            push @elems, _dump($elem);
        }
        return '['. join(', ', @elems) .']';
    }
    elsif (ref $arg eq 'HASH') {
        my @pairs;
        for my $key (keys %$arg) {
            push @pairs, [$key, _dump($arg->{$key})];
        }
        return '{'. join(', ', map { "$_->[0] => $_->[1]" } @pairs) .'}';
    }
    elsif (ref $arg) {
        require overload;
        return overload::StrVal($arg);
    }
    elsif (defined $arg) {
        return $arg if looks_like_number($arg);
        return "'".decode_irc($arg)."'";
    }
    else {
        return 'undef';
    }
}

sub _default {
    my ($self, $irc, $event) = splice @_, 0, 3;
    return PCI_EAT_NONE if $event eq 'S_raw';

    pop @_;
    my @args = map { $$_ } @_;
    my @output;

    for my $i (0..$#args) {
        push @output, "ARG$i: " . _dump($args[$i]);
    }

    for my $wheel_id ( keys %{ $self->{wheels} } ) {
        next if ( $self->{exit}->{ $wheel_id } or ( not defined ( $self->{wheels}->{ $wheel_id } ) ) );
        next if !$self->{authed}{ $wheel_id };
        $self->{wheels}->{ $wheel_id }->put("$event: ".join(', ', @output));
    }

    return PCI_EAT_NONE;
}

sub _start {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    $self->{SESSION_ID} = $_[SESSION]->ID();
    $kernel->refcount_increment( $self->{SESSION_ID}, __PACKAGE__ );
    $self->{ircd_filter} = POE::Filter::Stackable->new( Filters => [
        POE::Filter::Line->new(),
        POE::Filter::IRCD->new(),
    ]);

    $self->{listener} = POE::Wheel::SocketFactory->new(
        BindAddress  => 'localhost',
        BindPort     => $self->{bindport} || 0,
        SuccessEvent => '_listener_accept',
        FailureEvent => '_listener_failed',
        Reuse        => 'yes',
    );

    if ($self->{listener}) {
        $self->{irc}->send_event( 'irc_console_service' => $self->{listener}->getsockname() );
    }
    else {
        $self->{irc}->plugin_del( $self );
    }

    return;
}

sub _listener_accept {
    my ($kernel, $self, $socket, $peeradr, $peerport)
        = @_[KERNEL, OBJECT, ARG0 .. ARG2];

    my $wheel = POE::Wheel::ReadWrite->new(
        Handle       => $socket,
        InputFilter  => $self->{ircd_filter},
        OutputFilter => POE::Filter::Line->new(),
        InputEvent   => '_client_input',
        ErrorEvent   => '_client_error',
        FlushedEvent => '_client_flush',
    );

    if ( !defined $wheel ) {
        $self->{irc}->send_event( 'irc_console_rw_fail' => $peeradr => $peerport );
        return;
    }

    my $wheel_id = $wheel->ID();
    $self->{wheels}->{ $wheel_id } = $wheel;
    $self->{authed}->{ $wheel_id } = 0;
    $self->{exit}->{ $wheel_id } = 0;
    $self->{irc}->send_event( 'irc_console_connect' => $peeradr => $peerport => $wheel_id );

    return;
}

sub _listener_failed {
    delete $_[OBJECT]->{listener};
    return;
}

sub _client_input {
    my ($kernel, $self, $input, $wheel_id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if ($self->{authed}->{ $wheel_id } && lc ( $input->{command} ) eq 'exit') {
        $self->{exit}->{ $wheel_id } = 1;
        if (defined $self->{wheels}->{ $wheel_id }) {
            $self->{wheels}->{ $wheel_id }->put("ERROR * quiting *");
        }
        return;
    }

    if ( $self->{authed}->{ $wheel_id } ) {
        $self->{irc}->yield( lc ( $input->{command} ) => @{ $input->{params} } );
        return;
    }

    if (lc ( $input->{command} ) eq 'pass' && $input->{params}->[0] eq $self->{password} ) {
        $self->{authed}->{ $wheel_id } = 1;
        $self->{wheels}->{ $wheel_id }->put('NOTICE * Password accepted *');
        $self->{irc}->send_event( 'irc_console_authed' => $wheel_id );
        return;
    }

    $self->{wheels}->{ $wheel_id }->put('NOTICE * Password required * enter PASS <password> *');
    return;
}

sub _client_flush {
    my ($self, $wheel_id) = @_[OBJECT, ARG0];
    return if !$self->{exit}->{ $wheel_id };
    delete $self->{wheels}->{ $wheel_id };
    return;
}

sub _client_error {
    my ($self, $wheel_id) = @_[OBJECT, ARG3];

    delete $self->{wheels}->{ $wheel_id };
    delete $self->{authed}->{ $wheel_id };
    $self->{irc}->send_event( 'irc_console_close' => $wheel_id );
    return;
}

sub _shutdown {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    delete $self->{listener};
    delete $self->{wheels};
    delete $self->{authed};
    return;
}

sub getsockname {
    my $self = shift;
    return if !$self->{listener};
    return $self->{listener}->getsockname();
}

1;

=encoding utf8

=head1 NAME

POE::Component::IRC::Plugin::Console - A PoCo-IRC plugin that provides a
lightweight debugging and control console for your bot

=head1 SYNOPSIS

 use POE qw(Component::IRC Component::IRC::Plugin::Console);

 my $nickname = 'Flibble' . $$;
 my $ircname = 'Flibble the Sailor Bot';
 my $ircserver = 'irc.blahblahblah.irc';
 my $port = 6667;
 my $bindport = 6969;

 my @channels = ( '#Blah', '#Foo', '#Bar' );

 my $irc = POE::Component::IRC->spawn(
     nick => $nickname,
     server => $ircserver,
     port => $port,
     ircname => $ircname,
 ) or die "Oh noooo! $!";

 POE::Session->create(
     package_states => [
         main => [ qw(_start irc_001 irc_console_service irc_console_connect
             irc_console_authed irc_console_close irc_console_rw_fail) ],
         ],
 );

 $poe_kernel->run();

 sub _start {
     $irc->plugin_add( 'Console' => POE::Component::IRC::Plugin::Console->new(
         bindport => $bindport,
         password => 'opensesame'
     );
     $irc->yield( register => 'all' );
     $irc->yield( connect => { } );
     return;
  }

 sub irc_001 {
     $irc->yield( join => $_ ) for @channels;
     return;
 }

 sub irc_console_service {
     my $getsockname = $_[ARG0];
     return;
 }

 sub irc_console_connect {
     my ($peeradr, $peerport, $wheel_id) = @_[ARG0 .. ARG2];
     return;
 }

 sub irc_console_authed {
     my $wheel_id = $_[ARG0];
     return;
 }

 sub irc_console_close {
     my $wheel_id = $_[ARG0];
     return;
 }

 sub irc_console_rw_fail {
     my ($peeradr, $peerport) = @_[ARG0, ARG1];
     return;
 }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::Console is a L<POE::Component::IRC|POE::Component::IRC>
plugin that provides an interactive console running over the loopback network.
One connects to the listening socket using a telnet client (or equivalent),
authenticate using the applicable password. Once authed one will receive all
events that are processed through the component. One may also issue all the
documented component commands.

=head1 METHODS

=head2 C<new>

Takes two arguments:

B<'password'>, the password to set for *all* console connections;

B<'bindport'>, specify a particular port to bind to, defaults to 0, ie. randomly
allocated;

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head2 C<getsockname>

Gives access to the underlying listener's C<getsockname> method. See
L<POE::Wheel::SocketFactory|POE::Wheel::SocketFactory> for details.

=head1 OUTPUT EVENTS

The plugin generates the following additional
L<POE::Component::IRC|POE::Component::IRC> events:

=head2 C<irc_console_service>

Emitted when a listener is successfully spawned. C<ARG0> is the result of
C<getsockname>, see above for details.

=head2 C<irc_console_connect>

Emitted when a client connects to the console. C<ARG0> is the peeradr, C<ARG1>
is the peer port and C<ARG2> is the wheel id of the connection.

=head2 C<irc_console_authed>

Emitted when a client has successfully provided a valid password. C<ARG0> is
the wheel id of the connection.

=head2 C<irc_console_close>

Emitted when a client terminates a connection. C<ARG0> is the wheel id of the
connection.

=head2 C<irc_console_rw_fail>

Emitted when a L<POE::Wheel::ReadWrite|POE::Wheel::ReadWrite> could not be
created on a socket. C<ARG0> is the peer's address, C<ARG1> is the peer's port.

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>

L<POE::Wheel::SocketFactory|POE::Wheel::SocketFactory>

=cut
