#!/usr/bin/perl -w

package Standup;

use strict;
use base qw( Bot::BasicBot::Pluggable );

use Try::Tiny;
use Switch qw( Perl6 );
use Data::Dumper;
use List::Util qw( first shuffle );
use List::MoreUtils qw( first_index );
use POE qw(Component::Schedule);
use DateTime::Event::Cron;


my $VERSION = "1.1";


sub new {
    my $class = shift;
    return $class->SUPER::new(@_, in_progress => {}, joinlists => {});
}

sub init {
    my $self = shift;
    $self->SUPER::init() or return;
    my $logger = Log::Log4perl->get_logger( ref $self );

    STANDUP: for my $standup (@{ $self->{standups} }) {
        my $cronline = $standup->{schedule}
            or next STANDUP;

        my $when_iter = DateTime::Event::Cron->from_cron($cronline)->iterator(
            after => DateTime->now( time_zone => $standup->{schedule_tz} || q{UTC} ),
        );

        my $sesh = POE::Session->create( inline_states => {
            _start => sub {
                $_[HEAP]{sched} = POE::Component::Schedule->add($_[SESSION], schedalerm => $when_iter);
            },
            schedalerm => sub {
                $logger->debug("YAY SCHEDALERM FOR " . $standup->{id});
                $self->start_standup($standup);
            },
        } );
    }

    return 1;
}

sub get {
    my ($self, $name) = @_;
    return $self->store->get(ref $self, $name);
}

sub set {
    my ($self, $name, $value) = @_;
    return $self->store->set(ref $self, $name, $value);
}

# a standup is:
#   channel
#   last to join
#   who's gone
#   parking lot
#   start time
#   stop time

sub help {
    my ($self, $message) = @_;
    my $help = $message->{body};
    $help =~ s{ \A help \s* }{}msx;

    return q{My commands: standup, start, cancel, next, park, when} if !$help;

    given ($help) {
        when (/^standup$/) { return q{Tell me 'standup' to start a standup manually.} };
        when (/^start$/)   { return q{When starting a standup, tell me 'start' when everyone's arrived and I'll begin the standup.} };
        when (/^cancel$/)  { return q{When starting a standup, tell me 'cancel' (before we 'start') to forget about it.} };
        when (/^next$/)    { return q{During standup, tell me 'next' and I'll pick someone to go next. You can also tell me 'next <name>' to tell me <name> should go next.} };
        when (/^park$/)    { return q{During standup, tell me 'park <topic>' and I'll remind you about <topic> after we're done.} };
        when (/^when$/)    { return q{Tell me 'when' and I'll tell you when the next scheduled standup is.} };
        default            { return qq{I don't know what '$help' is.} };
    }
}

sub said {
    my ($self, $message) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );

    # Only care if we're addressed.
    return if !$message->{address};

    my ($command, $rest) = split / /, $message->{body}, 2;
    $command = lc $command;
    $message->{command} = $command;
    $message->{rest} = $rest;

    my $work = {
        hi      => q{hi},
        hello   => q{hi},
        standup => q{standup},
        start   => q{start},
        cancel  => q{cancel},
        park    => q{park},
        q{when} => q{when_standup},
        dump    => q{dump_data},
    }->{$command};

    # Be more liberal when matching the 'next' command.
    if (!$work && $message->{body} =~ m{ \b next \b }imsx) {
        $work = q{next_person};
    }

    if (!$work) {
        $logger->debug("$message->{who} told me to '$message->{body}' but what is that");
        return q{What? ('help' for help)};
    }

    try {
        return $self->can($work)->($self, $message);
    }
    catch {
        return "$_";
    };
}

sub hi {
    my ($self, $message) = @_;
    return "tender standup-bot $VERSION at your service.";
}

sub start_standup {
    my ($self, $standup) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );
    my $team = $standup->{id};

    # Are we already in a standup?
    if ($self->{in_progress}->{ $standup->{id} }) {
        $logger->debug("We were scheduled to start a $team standup, but there's already one going");
        return;
    }

    # Did we already have one of those today?
    my $now = DateTime->now( time_zone => $standup->{schedule_tz} || q{UTC} );
    if ($self->get(q{last_day_} . $team) eq $now->ymd) {
        $logger->debug("We were scheduled to start a $team standup, but we already had one for " . $now->ymd(q{/}));
        return;
    }

    # Pretend we were started manually, I guess.
    try {
        return $self->standup({ channel => $standup->{team_channel} });
    }
    catch {
        $logger->error("Tried to start scheduled standup '$team' but: $_");
    }
}

sub standup {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message, start => 1);
    my ($team, $team_chan, $standup_chan) = @$state{qw( id team_channel standup_channel )};

    my $now = DateTime->now( time_zone => $state->{schedule_tz} || q{UTC} );
    $self->set(q{last_day_} . $team, $now->ymd);

    my $logger = Log::Log4perl->get_logger( ref $self );
    $logger->debug("STANDUP self is $self, a " . ref($self));

    if ($team_chan ne $standup_chan) {
        $self->say(
            channel => $team_chan,
            body => qq{Time for standup! It's in $standup_chan},
        );
    }

    $self->say(
        channel => $standup_chan,
        body => q{Time for standup! Tell me 'start' when everyone's here.},
    );

    # Ask for an update about who's here, in case we got out of sync somehow.
    $self->names($standup_chan);

    return q{};
}

sub state_for_message {
    my ($self, $message, %args) = @_;

    my $channel = $message->{channel};
    die "What? There's no standup here!\n"
        if !$channel || $channel eq q{msg};

    # Which standup is that?
    my $standup = first {    $channel eq $_->{team_channel}
                          || $channel eq $_->{standup_channel} } @{ $self->{standups} };
    die "I don't know about the $channel standup.\n"
        if !$standup;

    return { %$standup } if $args{not_running};

    my $team = $standup->{id};
    my $state = $self->{in_progress}->{$team};

    if (!$state && $args{start}) {
        my %standup = %$standup;
        $self->{in_progress}->{$team} = $state = \%standup;
    }
    elsif (!$state) {
        die "There's no $team standup right now.\n";
    }

    return $state;
}

sub start {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message);

    return "The standup already started!"
        if $state->{started};

    $state->{started} = 1;
    $state->{gone} = {};
    $state->{parkinglot} = [];
    $state->{started} = time;

    return $self->next_person($message, pick_last => 1);
}

sub cancel {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message);

    return "The standup already started!"
        if $state->{started};

    if ($message->{channel} ne $state->{standup_channel}) {
        my $who = $message->{who};
        $self->say(
            channel => $state->{standup_channel},
            body => qq{Never mind, $who cancelled the standup.},
        );
    }

    delete $self->{in_progress}->{ $state->{id} };

    return "Cancelled.";
}

sub next_person {
    my ($self, $message, %args) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );
    my $state = $self->state_for_message($message);
    my $channel = $state->{standup_channel};

    # If it's not your turn, avoid double-nexting.
    my $not_my_turn = $state->{turn} && $state->{turn} ne $message->{who};
    if ($not_my_turn && time - ($state->{last_next} || 0) <= 5) {
        $logger->debug(sprintf "Only %d secs since last next, ignoring", time - $state->{last_next});
        return q{};
    }

    my $channel_data = $self->channel_data($channel);
    my @names = grep { defined $channel_data->{$_} } keys %$channel_data;
    $logger->debug("I see these folks in $channel: " . join(q{ }, @names));
    my %ignore = map { $_ => 1 } $self->ignore_list;

    # Were any of them also named in the message?
    my $next = first { $message->{body} =~ m{ \b \Q$_\E \b }imsx } @names;

    if (defined $next) {
        return qq{I'm a chicken and I don't call on chickens.} if $next eq $self->nick;
        return qq{$next is a chicken and I don't call on chickens.} if $ignore{$next};
        return qq{$next already went.} if $state->{gone}->{$next};
        return qq{It's already ${next}'s turn.} if $state->{turn} && $state->{turn} eq $next;
        $logger->debug("The nexter asked for $next to go next");
    }

    # You've gone when it's your turn and you ask to next.
    if ($state->{turn} && $state->{turn} eq $message->{who}) {
        $state->{gone}->{ $state->{turn} } = 1;
    }

    if (!defined $next) {
        @names = grep {
               !$state->{gone}->{$_}   # already went
            && $_ ne $self->nick       # the bot doesn't go
            && !$ignore{$_}            # other bots don't go
        } @names;
        $logger->debug("Minus all the chickens that's: " . join(q{ }, @names));

        # Was that everyone?
        return $self->done($message)
            if !@names;

        # If it's someone's turn but we're skipping them and there's someone else
        # to pick, don't pick whose turn it already is again immediately.
        if ($state->{turn} && !$state->{gone}->{ $state->{turn} } && @names > 1) {
            $logger->debug("Skipping $state->{turn} while there are others to pick");
            @names = grep { $_ ne $state->{turn} } @names;
        }

        # When appropriate, pick the last person we saw join the channel.
        PICKLAST: {
            if ($args{pick_last}) {
                $logger->debug("The last shall go first!");

                my $joinlist = $self->{joinlists}->{$channel};
                if (!$joinlist) {
                    $logger->debug("Oops, I don't know who joined $channel when; picking at random");
                    last PICKLAST;
                }

                my %eligible = map { $_ => 1 } @names;
                NICK: for my $nick (@$joinlist) {
                    next NICK if !$eligible{$nick};

                    $logger->debug("Looks like I saw $nick join last");
                    $next = $nick;
                    last PICKLAST;
                }

                $logger->debug("Hmm, I guess I didn't see when anyone who's left joined; picking at random");
            }
        };

        ($next, undef) = shuffle @names if !$next;
        $logger->debug("I picked $next to go next");
    }

    $state->{turn} = $next;
    $state->{last_next} = time;

    $self->say(
        channel => $channel,
        who     => $next,
        address => 1,
        body    => q{your turn},
    );

    return q{};
}

sub park {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message);

    push @{ $state->{parkinglot} }, $message->{rest};
    return "Parked.";
}

sub done {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message);

    # DONE
    delete $self->{in_progress}->{ $state->{id} };

    my $min_duration = int ((time - $state->{started}) / 60);
    $self->say(
        channel => $state->{standup_channel},
        body => sprintf(q{All done! Standup was %d minutes.}, $min_duration),
    );

    my $logger = Log::Log4perl->get_logger( ref $self );
    $logger->debug('Parked topics: ' . Dumper($state->{parkinglot}));
    if (my @parked = @{ $state->{parkinglot} }) {
        my $team = $state->{team_channel};
        $self->say(
            channel => $team,
            body => 'Parked topics:',
        );
        $self->say(
            channel => $team,
            body => ' * ' . $_,
        ) for @parked;
    }

    return q{};
}

sub when_standup {
    my ($self, $message) = @_;
    my $standup = $self->state_for_message($message, not_running => 1);
    my $now = DateTime->now( time_zone => $standup->{schedule_tz} || q{UTC} );
    my $team = $standup->{id};

    my $spec = $standup->{schedule}
        or return qq{The $team standup doesn't have a schedule.};
    my $sched = DateTime::Event::Cron->from_cron($spec);

    my $next_time = $sched->next($now);
    # But is that one scheduled later today, when we already held a manual standup?
    if ($self->get(qq{last_day_$team}) eq $next_time->ymd) {
        # Then it's the first one tomorrow.
        my $tomorrow = $now->clone->add( days => 1 )->truncate( to => q{day} );
        $next_time = $sched->next($tomorrow);
    }

    # Tell them!
    my $blah = q{Next standup is };
    $blah .= $now->ymd eq $next_time->ymd ? q{today}
           :                                $next_time->strftime(q{%A})
           ;

    $blah .= $next_time->strftime(q{ at HOUR%I:%M %P %Z});
    if ((my $addl_tz) = $standup->{additional_tz}) {
        $next_time->set_time_zone($addl_tz);
        $blah .= $next_time->strftime(q{ (HOUR%I:%M %P %Z)});
    }
    $blah =~ s{ HOUR 0? }{}gmsx;

    return $blah;
}

sub nick_change {
    my ($self, $old_nick, $new_nick) = @_;

    for my $joinlist (values %{ $self->{joinlists} }) {
        for my $nick (@{ $joinlist }) {
            $nick = $new_nick if $nick eq $old_nick;
        }
    }

    return q{};
}

sub chanjoin {
    my ($self, $message) = @_;
    my ($channel, $who) = @$message{qw( channel who )};

    my $joinlist = ($self->{joinlists}->{$channel} ||= []);
    @$joinlist = grep { $_ && $_ ne $who } @$joinlist;

    unshift @$joinlist, $who;
    return q{};
}

sub dump_data {
    my ($self, $message) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );

    my %data = %$self;
    delete $data{kernel};
    delete $data{session};

    $logger->debug(Data::Dumper->new([ \%data ])->Indent(2)->Dump());
    return q{};
}

sub tick {}


sub main {
    my $class = shift;

    require YAML;
    my $config = YAML::LoadFile(lc $class . '.yaml');

    # Join all the channels where there are standups or standup teams.
    my @channels = map { ($_->{team_channel}, $_->{standup_channel}) } @{ $config->{standups} };
    $config->{channels} = \@channels;

    my $bot = $class->new(%$config);
    $bot->run();
}

Standup->main() unless caller;

1;
