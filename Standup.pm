#!/usr/bin/perl -w

package Bot::BasicBot::Pluggable::Module::Standup;

use strict;
use base qw( Bot::BasicBot::Pluggable::Module );

use List::Util qw( first shuffle );


sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{standups} = {};
    return $self;
}

# a standup is:
#   channel
#   last to join
#   who's gone
#   parking lot
#   start time
#   stop time

sub help { q{whassap} }

sub told {
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
    $logger->debug("STANDUP bot is " . $self->bot . ", a " . ref($self->bot));

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
                          || $channel eq $_->{standup_channel} } @{ $self->get('standups') };
    die "I don't know about the $channel standup."
        if !$standup;

    my $team = $standup->{id};
    my $state = $self->{standups}->{$team};

    if (!$state && $args{start}) {
        my %standup = %$standup;
        $self->{standups}->{$team} = $state = \%standup;
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

    my @names = keys %{ $self->bot->channel_data($channel) };
    $logger->debug("I see these folks in $channel: " . join(q{ }, @names));

    my %ignore = map { $_ => 1 } $self->bot->ignore_list;
    @names = grep {
           !$state->{gone}->{$_}   # already went
        && $_ ne $self->bot->nick  # the bot doesn't go
        && !$ignore{$_}            # other bots don't go
    } @names;
    $logger->debug("Minus all the chickens that's: " . join(q{ }, @names));

    return $self->done($message)
        if !@names;

    my $next = first { 1 } shuffle @names;
    $state->{turn} = $next;
    $logger->debug("I picked $next to go next");

    $self->bot->say(
        channel => $channel,
        who     => $next,
        address => 1,
        body    => q{your turn},
    );

    return q{};
}

sub done {
    my ($self, $message) = @_;
    my $state = $self->state_for_message($message);

    # DONE
    delete $self->{standups}->{ $state->{id} };

    $self->bot->say(
        channel => $state->{standup_channel},
        body => q{All done!},
    );

    return q{};
}

sub tick {
    return 0;
}

1;
