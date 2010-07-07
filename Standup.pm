#!/usr/bin/perl -w

package Standup;

use strict;
use base qw( Bot::BasicBot::Pluggable );
use feature q{switch};

use Data::Dumper;
use List::Util qw( first shuffle );


sub new {
    my $class = shift;
    return $class->SUPER::new(@_, in_progress => {});
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

    return q{My commands: standup, start, next, park} if !$help;

    given ($help) {
        when (/^standup$/) { return q{Tell me 'standup' to start a standup manually.} };
        when (/^start$/)   { return q{When starting a standup, tell me 'start' when everyone's arrived to begin.} };
        when (/^next$/)    { return q{During standup, tell me 'next' and I'll pick someone to go next.} };
        when (/^park$/)    { return q{During standup, tell me 'park <topic>' and I'll remind you about <topic> after standup.} };
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
        standup => q{standup},
        start   => q{start},
        q{next} => q{next_person},
        park    => q{park},
    }->{$command};
    return if !$work;

    try {
        return $self->can($work)->($self, $message);
    }
    catch {
        return "$_";
    };
}

sub hi {
    my ($self, $message) = @_;
    return 'o hai.';
}

sub standup {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message, start => 1);
    my ($team, $team_chan, $standup_chan) = @$state{qw( id team_channel standup_channel )};

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

    return q{};
}

sub state_for_message {
    my ($self, $message, %args) = @_;

    my $channel = $message->{channel};
    die "What? There's no standup here!"
        if !$channel || $channel eq q{msg};

    # Which standup is that?
    my $standup = first {    $channel eq $_->{team_channel}
                          || $channel eq $_->{standup_channel} } @{ $self->{standups} };
    die "I don't know about the $channel standup."
        if !$standup;

    my $team = $standup->{id};
    my $state = $self->{in_progress}->{$team};

    if (!$state && $args{start}) {
        my %standup = %$standup;
        $self->{in_progress}->{$team} = $state = \%standup;
    }
    elsif (!$state) {
        die "There's no $team standup right now.";
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

    return $self->next_person($message);
}

sub next_person {
    my ($self, $message) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );
    my $state = $self->state_for_message($message);
    my $channel = $state->{standup_channel};

    # You've gone when it's your turn and you ask to next.
    if ($state->{turn} && $state->{turn} eq $message->{who}) {
        $state->{gone}->{ $state->{turn} } = 1;
    }
    # If it's not your turn, avoid double-nexting.
    elsif ($state->{turn} && time - ($state->{last_next} || 0) <= 15) {
        $logger->debug(sprintf "Only %d secs since last next, ignoring", time - $state->{last_next});
        return q{};
    }

    my @names = keys %{ $self->channel_data($channel) };
    $logger->debug("I see these folks in $channel: " . join(q{ }, @names));

    my %ignore = map { $_ => 1 } $self->ignore_list;
    @names = grep {
           !$state->{gone}->{$_}   # already went
        && $_ ne $self->nick       # the bot doesn't go
        && !$ignore{$_}            # other bots don't go
    } @names;
    $logger->debug("Minus all the chickens that's: " . join(q{ }, @names));

    return $self->done($message)
        if !@names;

    # If it's someone's turn but we're skipping them and there's someone else
    # to pick, don't pick whose turn it already is again immediately.
    if ($state->{turn} && !$state->{gone}->{ $state->{turn} } && @names > 1) {
        $logger->debug("Skipping $state->{turn} while there are others to pick");
        @names = grep { $_ ne $state->{turn} } @names;
    }

    my $next = first { 1 } shuffle @names;
    $state->{turn} = $next;
    $state->{last_next} = time;
    $logger->debug("I picked $next to go next");

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
        $self->tell($team, 'Parked topics:');
        $self->tell($team, ' * ' . $_) for @parked;
    }

    return q{};
}

sub tick {
    return 0;
}


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
