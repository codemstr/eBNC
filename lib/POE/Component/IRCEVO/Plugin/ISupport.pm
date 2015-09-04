package POE::Component::IRC::Plugin::ISupport;
BEGIN {
  $POE::Component::IRC::Plugin::ISupport::AUTHORITY = 'cpan:HINRIK';
}
$POE::Component::IRC::Plugin::ISupport::VERSION = '6.88';
use strict;
use warnings FATAL => 'all';
use POE::Component::IRC::Plugin qw(:ALL);

sub new {
    return bless { }, shift;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;

    $irc->plugin_register( $self => SERVER => qw(all) );
    $self->{irc} = $irc;
    $self->{parser} = {
        CASEMAPPING => sub {
            my ($support, $key, $val) = @_;
            $support->{$key} = $val;
        },
        CHANLIMIT => sub {
            my ($support, $key, $val) = @_;
            while ($val =~ /([^:]+):(\d+),?/g) {
                my ($k, $v) = ($1, $2);
                @{ $support->{$key} }{ split(//, $k) } = ($v) x length $k;
            }
        },
        CHANMODES => sub {
            my ($support, $key, $val) = @_;
            $support->{$key} = [ split(/,/, $val) ];
        },
        CHANTYPES => sub {
            my ($support, $key, $val) = @_;
            $support->{$key} = [ split(//, $val) ];
        },
        ELIST => sub {
            my ($support, $key, $val) = @_;
            $support->{$key} = [ split(//, $val) ];
        },
        IDCHAN => sub {
            my ($support, $key, $val) = @_;
            while ($val =~ /([^:]+):(\d+),?/g) {
                my ($k, $v) = ($1, $2);
                @{ $support->{$key} }{ split(//, $k) } = ($v) x length $k;
            }
        },
        MAXLIST => sub {
            my ($support, $key, $val) = @_;
            while ($val =~ /([^:]+):(\d+),?/g) {
                my ($k, $v) = ($1, $2);
                @{ $support->{$key} }{ split(//, $k) } = ($v) x length $k;
            }
        },
        PREFIX => sub {
            my ($support, $key, $val) = @_;
            if (my ($k, $v) = $val =~ /\(([^)]+)\)(.*)/ ) {
                @{ $support->{$key} }{ split(//, $k) } = split(//, $v);
            }
        },
        STATUSMSG => sub {
            my ($support, $key, $val) = @_;
            $support->{$key} = [ split(//, $val) ];
        },
        TARGMAX => sub {
            my ($support, $key, $val) = @_;
            while ($val =~ /([^:]+):(\d*),?/g) {
                my ($k, $v) = ($1, $2);
                $support->{$key}->{$k} = $v;
            }
        },
        EXCEPTS => sub {
            my ($support, $flag) = @_;
            $support->{$flag} = 'e';
        },
        INVEX => sub {
            my ($support, $flag) = @_;
            $support->{$flag} = 'I';
        },
    };

    return 1;
}

sub PCI_unregister {
    my ($self, $irc) = splice @_, 0, 2;
    delete $self->{irc};
    return 1;
}

sub S_connected {
    my ($self, $irc) = splice @_, 0, 2;

    $self->{server}   = { };
    $self->{got_005}  = 0;
    $self->{done_005} = 0;
    return PCI_EAT_NONE;
}

sub S_005 {
    my ($self, $irc, @args) = @_;
    my @vals = @{ ${ $args[2] } };
    pop @vals;
    my $support = $self->{server};

    for my $val (@vals) {
        if ($val =~ /=/) {
            my $key;
            ($key, $val) = split(/=/, $val, 2);
            if (defined $self->{parser}->{$key}) {
                $self->{parser}->{$key}->($support, $key, $val);
            }
            else {
                # AWAYLEN CHANNELLEN CHIDLEN CHARSET EXCEPTS INVEX KICKLEN
                # MAXBANS MAXCHANNELS MAXTARGETS MODES NETWORK NICKLEN STD
                # TOPICLEN WATCH
                $support->{$key} = $val;
            }
        }
        else {
            if (defined $self->{parser}->{$val}) {
                $self->{parser}->{$val}->($support, $val);
            }
            else {
                # ACCEPT CALLERID CAPAB CNOTICE CPRIVMSG FNC KNOCK MAXNICKLEN
                # NAMESX NOQUIT PENALTY RFC2812 SAFELIST UHNAMES USERIP
                # VCHANS WALLCHOPS WALLVOICES WHOX
                $support->{$val} = 'on';
            }
        }
    }

    $self->{got_005}++;
    return PCI_EAT_NONE;
}

sub _default {
    my ($self, $irc, $event) = @_;

    return PCI_EAT_NONE if $self->{done_005};
    return PCI_EAT_NONE if !$self->{got_005};

    if ($event =~ /^S_(\d+)/ and $1 > 5) {
        $self->{done_005} = 1;
        $irc->send_event_now(irc_isupport => $self);
    }

    return PCI_EAT_NONE;
}

sub isupport {
    my $self = shift;
    my $value = uc ( $_[0] ) || return;

    return $self->{server}->{$value} if defined $self->{server}->{$value};
    return;
}

sub isupport_dump_keys {
    my $self = shift;

    if ( keys %{ $self->{server} } > 0 ) {
        return keys %{ $self->{server} };
    }
    return;
}

1;

=encoding utf8

=head1 NAME

POE::Component::IRC::Plugin::ISupport - A PoCo-IRC plugin that handles server
capabilities

=head1 DESCRIPTION

This handles the C<irc_005> messages that come from the server.  They
define the capabilities support by the server.

=head1 METHODS

=head2 C<new>

Takes no arguments.

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head2 C<isupport>

Takes one argument. the server capability to query. Returns a false value on
failure or a value representing the applicable capability. A full list of
capabilities is available at L<http://www.irc.org/tech_docs/005.html>.

=head2 C<isupport_dump_keys>

Takes no arguments, returns a list of the available server capabilities,
which can be used with C<isupport>.

=head1 INPUT

This module handles the following PoCo-IRC signals:

=head2 C<irc_005> (RPL_ISUPPORT or RPL_PROTOCTL)

Denotes the capabilities of the server.

=head2 C<all>

Once the next signal is received that is I<greater> than C<irc_005>,
it emits an C<irc_isupport> signal.

=head1 OUTPUT EVENTS

=head2 C<irc_isupport>

Emitted by: the first signal received after C<irc_005>

C<ARG0> will be the plugin object itself for ease of use.

This is emitted when the support report has finished.

=head1 AUTHOR

Jeff C<japhy> Pinyan, F<japhy@perlmonk.org>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>

L<POE::Component::IRC::Plugin|POE::Component::IRC::Plugin>

=cut
