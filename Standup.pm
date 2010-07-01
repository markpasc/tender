#!/usr/bin/perl -w

package Bot::BasicBot::Pluggable::Module::Standup;

use strict;
use base qw( Bot::BasicBot::Pluggable::Module );

sub help { q{whassap} }

use Data::Dumper;
sub told {
    my ($self, $message) = @_;
    my $logger = Log::Log4perl->get_logger( ref $self );

    return if !$message->{address};

    my ($command, $rest) = split / /, $message->{body}, 2;
    $command = lc $command;
    $message->{command} = $command;
    $message->{rest} = $rest;

    my $work = {
        hi => \&hi,
    }->{$command};
    return if !defined $work;

    return $work->($self, $message);
}

sub hi {
    my ($self, $message) = @_;
    $self->reply($message, 'o hai.');
    return;
}

sub tick {
    return 0;
}

1;
