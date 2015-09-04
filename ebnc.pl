#!/usr/bin/perl
 use warnings;
 use strict;
 use lib "lib/";
 use POE;
 use POE qw(Component::IRC::State Component::IRC::Plugin::Proxy Component::IRC::Plugin::Connector);
 use POE::Component::Server::HTTP;
 use HTTP::Status;
 use IRC::Utils qw(parse_user lc_irc);

 use Exporter;
 use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
 use EvoTool;
######################################################
# Perl BNC Server for 4x4 Evolution eircd-hybrid-8.3 #
# ################################################## #
######################################################
our $VERSION = 'v1.0';
my $range = 1450;
my $max = 7999;
my $port = int(rand($range)) + $max;
my $challenge = $ARGV[2] || undef;
my $password;
my $bnc_password = 'evobnc';
my $ip = '192.168.254.75';
my $myip = $ip;
my $longip = longIp($ip);
my $nick = EvoTool::mangleNick($ip,$port); 
my $username = '00000000.4x4evo-perlbnc-1';
my $bindhost = '192.168.254.75';#
my $bot_realname = 'Evo BNC ' . $VERSION;
my $irc_server = "192.168.254.75";
my @channels = ('#Main', '#Revo', '#EvoR');

my $irc = POE::Component::IRC::State->spawn();

 POE::Session->create(
     package_states => [
         main => [ qw(
		 _default
		 _start 
		irc_001
		irc_challenge
		irc_join 
		irc_proxy_connect
	) ],
     ],
     heap => { irc => $irc },
 );
 $poe_kernel->run();

 sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    $heap->{irc}->yield( register => qw(all) );
    $heap->{proxy} = POE::Component::IRC::Plugin::Proxy->new( bindaddress => $bindhost, bindport => 6868, password => $bnc_password);
    $heap->{irc}->plugin_add( 'Connector' => POE::Component::IRC::Plugin::Connector->new( Flood => 1, Raw  => 1) );
    $heap->{irc}->plugin_add( 'Proxy' => $heap->{proxy} );
    $heap->{irc}->yield ( connect => { Nick => $nick, Username => $username, Server => $irc_server, Ircname => $bot_realname .'^0' } );		
    return;
 }

 sub irc_001 {
     my $sender = $_[SENDER];
     my $irc = $sender->get_heap();
     print "Connected to ", $irc->server_name(), "\n";
     $irc->yield( join => $_ ) for @channels;
     return;
 }

 sub irc_challenge {
  my ($kernel, $challenge) = @_[KERNEL, ARG0];
  if ($challenge) {
        chomp($challenge);
        my $n = 256;
        my $long = unpack 'N!', pack 'C4', split /\./, $myip;
        if (defined $long) {
                chomp($long);
                if ($nick) {
                 my $password = EvoTool::Evo2Password($nick, $long, $challenge);
                        if (defined $password) {
                                chomp($password);
                                $irc->yield( quote => "PASS $password" );
                                $irc->yield( quote => "NICK $nick");
                                $irc->yield( quote => "USER $username $ip $irc_server :$bot_realname^0");
                        }
                }
        }

  } else {
        print "*** Error getting challenge code!\n";
  }
return;
}


sub irc_join  {
        my ($kernel, $sender, $who, $where) = @_[KERNEL, SENDER, ARG0, ARG1, ARG2];
        my $unick        = (split /!/, $who)[0];
        my $identd_host = (split /!/, $who)[1];
        my $identd      = (split /@/, $identd_host)[0];
        my $host        = (split /@/, $identd_host)[1];
        my $channel = $where;
        my $delay = 5;
        my $limit = 3;
        my $obj = $sender->get_heap();
        my $chan_limit = $obj->channel_limit($channel);
        my @total_nicks = $obj->nicks();
        my $count = @total_nicks;
        my @nics = $obj->nicks();
        my $AmIop = $obj->is_channel_operator( $channel, $nick);
        my $HasVoice = $obj->has_channel_voice( $channel, $unick );

        if ($unick eq $nick) { 
                $irc->yield( quote => "RCHG :$bot_realname^0" );
                privmsg($channel, "^STATUS $bot_realname^0");
        }
}

sub irc_proxy_connect {
  my ($args) = @_[ARG0 .. $#_];
    
  print "ARG: $args\n"; 
}

sub privmsg {
        my ($channel, $msg) = @_;
        $irc->yield(privmsg => $channel, $msg);
        return;
}

sub _default {
     my ($event, $args) = @_[ARG0 .. $#_];
     my @output = ( "$event: " );

     for my $arg (@$args) {
         if ( ref $arg eq 'ARRAY' ) {
             push( @output, '[' . join(', ', @$arg ) . ']' );
         }
         else {
             push ( @output, "'$arg'" );
         }
     }
     #print join ' ', @output, "\n";
     return;
 }

sub longIp {
   return unpack 'N!', pack 'C4', split /\./, shift;
}
