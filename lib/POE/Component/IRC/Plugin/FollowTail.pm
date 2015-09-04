package POE::Component::IRC::Plugin::FollowTail;
BEGIN {
  $POE::Component::IRC::Plugin::FollowTail::AUTHORITY = 'cpan:HINRIK';
}
$POE::Component::IRC::Plugin::FollowTail::VERSION = '6.88';
use strict;
use warnings FATAL => 'all';
use Carp;
use File::Glob ':glob';
use File::Spec::Functions 'rel2abs';
use POE qw(Wheel::FollowTail);
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
    my ($package) = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %args = @_;
    $args{lc $_} = delete $args{$_} for keys %args;

    die "$package requires a 'filename' attribute" if !defined $args{filename};
    $args{filename} = bsd_glob($args{filename});
    die "File '$args{filename}' does not exist" if !-e $args{filename};
    $args{filename} = rel2abs($args{filename});

    return bless \%args, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;
    $self->{irc} = $irc;
    POE::Session->create(
        object_states => [
            $self => [ qw(_start _shutdown _input _error _reset) ],
        ],
    );

    return 1;
}

sub PCI_unregister {
    my ($self, $irc) = splice @_, 0, 2;
    delete $self->{irc};
    $poe_kernel->post( $self->{session_id} => '_shutdown' );
    $poe_kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
    return 1;
}

sub _start {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    $self->{session_id} = $_[SESSION]->ID();
    $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );

    $self->{wheel} = POE::Wheel::FollowTail->new(
        Filename     => $self->{filename},
        InputEvent   => '_input',
        ErrorEvent   => '_error',
        ResetEvent   => '_reset',
        ( defined $self->{filter} && $self->{filter}->isa('POE::Filter')
            ? ( Filter => $self->{filter} )
            : ()
        ),
    );

    return;
}

sub _shutdown {
    my ($kernel, $self, $term) = @_[KERNEL, OBJECT, ARG0];
    delete $self->{wheel};
    $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ ) if $term;
    return;
}

sub _input {
    my ($kernel, $self, $input) = @_[KERNEL, OBJECT, ARG0];
    $self->{irc}->send_event( 'irc_tail_input', $self->{filename}, $input );
    return;
}

sub _error {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $self->{irc}->send_event( 'irc_tail_error', $self->{filename}, @_[ARG0..ARG2] );
    $kernel->yield('_shutdown','TERM');
    return;
}

sub _reset {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $self->{irc}->send_event( 'irc_tail_reset', $self->{filename} );
    return;
}

1;

=encoding utf8

=head1 NAME

POE::Component::IRC::Plugin::FollowTail - A PoCo-IRC plugin to follow the tail
of an ever-growing file

=head1 SYNOPSIS

 use POE qw(Component::IRC Component::IRC::Plugin::FollowTail);

 my $nickname = 'Flibble' . $$;
 my $ircname = 'Flibble the Sailor Bot';
 my $ircserver = 'irc.blahblahblah.irc';
 my $filename = '/some/such/file/here';
 my @channels = ( '#Blah', '#Foo', '#Bar' );

 my $irc = POE::Component::IRC->spawn(
     nick => $nickname,
     server => $ircserver,
     port => $port,
     ircname => $ircname,
 ) or die "Oh noooo! $!";

 POE::Session->create(
     package_states => [
         main => [ qw(_start irc_001 irc_tail_input irc_tail_error irc_tail_reset) ],
     ],
 );

  $poe_kernel->run();

 sub _start {
     $irc->plugin_add( 'FollowTail' => POE::Component::IRC::Plugin::FollowTail->new(
         filename => $filename,
     ));
     $irc->yield( register => 'all' );
     $irc->yield( connect => { } );
     return;
 }

 sub irc_001 {
     $irc->yield( join => $_ ) for @channels;
     return;
 }

 sub irc_tail_input {
     my ($kernel, $sender, $filename, $input) = @_[KERNEL, SENDER, ARG0, ARG1];
     $kernel->post( $sender, 'privmsg', $_, "$filename: $input" ) for @channels;
     return;
 }

 sub irc_tail_error {
     my ($kernel, $sender, $filename, $errnum, $errstring)
         = @_[KERNEL, SENDER, ARG0 .. ARG2];
     $kernel->post( $sender, 'privmsg', $_, "$filename: ERROR: $errnum $errstring" ) for @channels;
     $irc->plugin_del( 'FollowTail' );
     return;
 }

 sub irc_tail_reset {
     my ($kernel, $sender, $filename) = @_[KERNEL, SENDER, ARG0];
     $kernel->post( $sender, 'privmsg', $_, "$filename: RESET EVENT" ) for @channels;
     return;
 }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::FollowTail is a L<POE::Component::IRC|POE::Component::IRC>
plugin that uses L<POE::Wheel::FollowTail|POE::Wheel::FollowTail> to follow
the end of an ever-growing file. It generates C<irc_tail_> prefixed events for
each new record that is appended to its file.

=head1 METHODS

=head2 C<new>

Takes two arguments:

B<'filename'>, the name of the file to tail, mandatory;

B<'filter'>, a POE::Filter object to pass to POE::Wheel::FollowTail, optional;

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head1 OUTPUT EVENTS

The plugin generates the following additional
L<POE::Component::IRC|POE::Component::IRC> events:

=head2 C<irc_tail_input>

Emitted for every complete record read. C<ARG0> will be the filename,
C<ARG1> the record which was read.

=head2 C<irc_tail_error>

Emitted whenever an error occurs. C<ARG0> will be the filename, C<ARG1>
and C<ARG2> hold numeric and string values for $!, respectively.

=head2 C<irc_tail_reset>

Emitted every time a file is reset. C<ARG0> will be the filename.

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>

L<POE::Wheel::FollowTail|POE::Wheel::FollowTail>

=cut
