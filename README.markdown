## tender, a bot for running agile style standups in IRC ##

tender is an IRC bot that helps you run standups for distributed teams using IRC.

    #team:
    [11:00] <      tender> Time for standup! It's in #standup

    #standup:
    [11:00] <      tender> Time for standup! Tell me 'start' when everyone's
                           here.
    [11:00]            --> bob has joined #standup
    [11:00]            --> alice has joined #standup
    [11:00] <    markpasc> tender: start
    [11:00] <      tender> alice: your turn
    [11:00] <       alice> i did some stuff and it was pretty awesome
    [11:00] <       alice> tender: next
    [11:00] <      tender> bob: your turn
    [11:01] <         bob> i also got some things done
    [11:01] <         bob> today i'm hell of rocking something else
    [11:01] <         bob> i forgot i had to talk to alice about getting the
                           splines reticulated though
    [11:02] <       alice> tender: park reticulating the splines
    [11:02] <      tender> alice: Parked.
    [11:02] <         bob> tender: next
    [11:02] <      tender> markpasc: your turn
    [11:02] <    markpasc> i also did some awesome stuff but today's stuff is
                           even more awesomer
    [11:02] <    markpasc> tender: next
    [11:02] <      tender> All done! Standup was 2 minutes.

    back in #team:
    [11:02] <      tender> Parked topics:
    [11:02] <      tender>  * reticulating the splines


### Getting started ###

You'll need these things to run tender:

* Perl 5.10
* Bot::BasicBot::Pluggable
* Try::Tiny
* POE::Component::Schedule
* DateTime::Event::Cron

Once you have these, copy the `standup-example.yaml` to `standup.yaml` and customize it for your team. Specify any of [Bot::BasicBot's attributes][bbnew] to set them for your bot. One attribute of particular note is:

* `ignore_list`: the names of people to ignore. Include the other bots you use in your standup channel here and they won't be called on.

The standups are configured in the `standups` setting. It's a list in case you want to run multiple standups on your server, but you probably only have one at first. For each standup you can specify:

* `id`: a code name for that team.
* `team_channel`: the channel the team normally chats in. The bot announces standups to this channel, and afterward pastes the parking lot there.
* `standup_channel`: the channel to run the standup in. Anyone in this channel (except for other bots named in the `ignore_list`) are considered "the team" and will be called on during the standup. If you have no lurking chickens, this can be the same as the `team_channel`.
* `schedule`: a cron style specification for when your standups are. See `man 5 crontab` for how to write one of these. If not specified, standups only happen when started manually with the `standup` command.
* `schedule_tz`: the time zone `schedule` is specified in. This is also the main time zone used by the `when` command, so it should be the primary time zone for your team. If not specified, times are in UTC.
* `additional_tz`: another time zone your team uses. The `when` command also says what time the next standup is in this time zone. If not specified, `when` only lists one time zone.

Once you've configured it, run:

    $ perl Standup.pm

to start the bot.

[bbnew]: http://search.cpan.org/dist/Bot-BasicBot/lib/Bot/BasicBot.pm#ATTRIBUTES


### Using tender ###

Ask tender for `help` to see its commands.
